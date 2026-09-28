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
