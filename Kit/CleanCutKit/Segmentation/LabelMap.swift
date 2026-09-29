import CoreGraphics

/// A low-resolution map of instance labels (`0` = background, `1...n` = objects)
/// with a top-left origin, as produced by instance segmentation.
///
/// Small enough (~500 px) to scan on the CPU, which makes hit-testing and bounding
/// boxes cheap, deterministic and easy to unit-test.
public struct LabelMap: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public let labels: [UInt8]

    public init(width: Int, height: Int, labels: [UInt8]) {
        precondition(width > 0 && height > 0 && labels.count == width * height, "label buffer size mismatch")
        self.width = width
        self.height = height
        self.labels = labels
    }

    public subscript(x: Int, y: Int) -> UInt8 {
        labels[y * width + x]
    }

    /// Every non-background label present in the map, ascending.
    public var instances: [Int] {
        var seen = [Bool](repeating: false, count: 256)
        for label in labels where label != 0 { seen[Int(label)] = true }
        return seen.indices.filter { seen[$0] }
    }

    /// The label under a normalized point (top-left origin), or `nil` if the
    /// point is outside the map.
    public func label(atNormalized point: CGPoint) -> Int? {
        guard (0...1).contains(point.x), (0...1).contains(point.y) else { return nil }
        let x = min(Int(point.x * CGFloat(width)), width - 1)
        let y = min(Int(point.y * CGFloat(height)), height - 1)
        return Int(self[x, y])
    }

    /// Normalized bounding box (top-left origin) of the given instances, or `nil`
    /// if none of their pixels are present.
    public func boundingBox(of instances: Set<Int>) -> CGRect? {
        var lookup = [Bool](repeating: false, count: 256)
        for instance in instances where (1...255).contains(instance) { lookup[instance] = true }

        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let row = y * width
            for x in 0..<width where lookup[Int(labels[row + x])] {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(
            x: CGFloat(minX) / CGFloat(width),
            y: CGFloat(minY) / CGFloat(height),
            width: CGFloat(maxX - minX + 1) / CGFloat(width),
            height: CGFloat(maxY - minY + 1) / CGFloat(height)
        )
    }
}

/// Resolves a tap to an instance.
public enum InstanceHitTester {
    /// The instance under `point`, or — when the tap lands on background — the
    /// nearest instance within `snapRadius` (normalized to the map's short side).
    /// Fingers are imprecise; a tap just outside a thin object should still hit it.
    public static func instance(at point: CGPoint, in map: LabelMap, snapRadius: CGFloat = 0.04) -> Int? {
        guard let direct = map.label(atNormalized: point) else { return nil }
        if direct != 0 { return direct }

        let shortSide = CGFloat(min(map.width, map.height))
        let radius = Int((snapRadius * shortSide).rounded(.up))
        guard radius > 0 else { return nil }

        let cx = min(Int(point.x * CGFloat(map.width)), map.width - 1)
        let cy = min(Int(point.y * CGFloat(map.height)), map.height - 1)
        var best: (label: Int, distance: Int)?
        for y in max(0, cy - radius)...min(map.height - 1, cy + radius) {
            for x in max(0, cx - radius)...min(map.width - 1, cx + radius) {
                let label = Int(map[x, y])
                guard label != 0 else { continue }
                let distance = (x - cx) * (x - cx) + (y - cy) * (y - cy)
                if distance <= radius * radius, distance < (best?.distance ?? .max) {
                    best = (label, distance)
                }
            }
        }
        return best?.label
    }
}

extension LabelMap {
    /// Splits the foreground into its separate objects: each 8-connected region
    /// becomes its own instance, largest first.
    ///
    /// Salient-object models (U²-Netp) return one mask for everything in the
    /// photo; splitting it is what lets tap-to-select work without Vision.
    /// Regions smaller than `minimumArea` (a fraction of the map) are specks of
    /// the same product, too small to tap, so they join the nearest object
    /// rather than being dropped: every foreground pixel keeps an owner.
    public func separatingObjects(minimumArea: Double = 0.001) -> LabelMap {
        let (component, areas) = connectedComponents()

        // Keep the regions big enough to tap (always at least the largest),
        // numbered largest first.
        let minimumPixels = Int((minimumArea * Double(labels.count)).rounded(.up))
        let ranked = areas.indices.sorted { areas[$0] > areas[$1] }
        let kept = ranked.enumerated()
            .filter { rank, id in rank == 0 || areas[id] >= minimumPixels }
            .prefix(255)
        var instance = [UInt8](repeating: 0, count: areas.count)
        for (rank, id) in kept { instance[id] = UInt8(rank + 1) }

        var separated = [UInt8](repeating: 0, count: labels.count)
        for i in labels.indices where component[i] >= 0 { separated[i] = instance[Int(component[i])] }
        guard kept.count < areas.count else {
            return LabelMap(width: width, height: height, labels: separated)
        }
        // Specks join the nearest kept object.
        let owners = LabelMap(width: width, height: height, labels: separated).nearestInstances()
        for i in labels.indices where labels[i] != 0 { separated[i] = owners.labels[i] }
        return LabelMap(width: width, height: height, labels: separated)
    }

    /// 8-connected regions of the foreground: each pixel's region index (`-1`
    /// for background) and each region's area.
    private func connectedComponents() -> (component: [Int32], areas: [Int]) {
        var component = [Int32](repeating: -1, count: labels.count)
        var areas: [Int] = []
        var stack: [Int] = []
        labels.withUnsafeBufferPointer { labels in
            component.withUnsafeMutableBufferPointer { component in
                for start in labels.indices where labels[start] != 0 && component[start] < 0 {
                    let id = Int32(areas.count)
                    var area = 0
                    component[start] = id
                    stack.append(start)
                    while let i = stack.popLast() {
                        area += 1
                        let x = i % width, y = i / width
                        for ny in max(0, y - 1)...min(height - 1, y + 1) {
                            for nx in max(0, x - 1)...min(width - 1, x + 1) {
                                let n = ny * width + nx
                                if labels[n] != 0, component[n] < 0 {
                                    component[n] = id
                                    stack.append(n)
                                }
                            }
                        }
                    }
                    areas.append(area)
                }
            }
        }
        return (component, areas)
    }

    /// Labels every pixel, background included, with the nearest instance
    /// (4-connected distance), partitioning the whole map between instances.
    ///
    /// Splitting a soft mask with this partition keeps each object's soft edge
    /// whole: the seams run through background, where coverage is ~0.
    public func nearestInstances() -> LabelMap {
        var owners = labels
        var queue = [Int]()
        queue.reserveCapacity(labels.count)
        for i in labels.indices where labels[i] != 0 { queue.append(i) }
        guard !queue.isEmpty else { return self }
        // Breadth-first from every instance at once: the first to reach a pixel
        // is (one of) the nearest.
        owners.withUnsafeMutableBufferPointer { owners in
            var head = 0
            while head < queue.count {
                let i = queue[head]
                head += 1
                let x = i % width
                let owner = owners[i]
                @inline(__always) func visit(_ n: Int) {
                    if owners[n] == 0 {
                        owners[n] = owner
                        queue.append(n)
                    }
                }
                if x > 0 { visit(i - 1) }
                if x < width - 1 { visit(i + 1) }
                if i >= width { visit(i - width) }
                if i + width < owners.count { visit(i + width) }
            }
        }
        return LabelMap(width: width, height: height, labels: owners)
    }
}
