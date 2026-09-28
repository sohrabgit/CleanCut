import CoreGraphics
import CoreImage
import Foundation

/// Finds the foreground objects in an image.
///
/// The pipeline never talks to Vision or Core ML directly; it consumes a
/// `SegmentationResult`. That keeps the pipeline testable with synthetic masks and
/// lets the benchmark swap engines.
public protocol Segmenter: Sendable {
    /// A short human-readable engine name, e.g. "Vision".
    var name: String { get }

    /// Segments an upright (`.up`-oriented) image.
    func segment(_ image: CGImage) async throws -> SegmentationResult
}

public enum SegmentationError: Error, Equatable, Sendable {
    /// Nothing that looks like a product was found.
    case noSubject
    /// The engine can't run here (e.g. Vision's instance mask in the Simulator).
    case unavailable(String)
    case failed(String)
}

/// The output of a segmenter: instance labels for interaction plus a way to build
/// a full-resolution soft mask for any selection.
public struct SegmentationResult: Sendable {
    /// Pixel size of the segmented image; masks are produced at this size.
    public let imageSize: CGSize
    /// Low-resolution instance labels, for hit-testing and bounding boxes.
    public let labelMap: LabelMap
    /// Available instance indices, ascending.
    public let instances: [Int]

    private let makeMask: @Sendable (IndexSet) throws -> CIImage

    public init(
        imageSize: CGSize,
        labelMap: LabelMap,
        instances: [Int],
        makeMask: @escaping @Sendable (IndexSet) throws -> CIImage
    ) {
        self.imageSize = imageSize
        self.labelMap = labelMap
        self.instances = instances
        self.makeMask = makeMask
    }

    /// Resolves `nil` ("everything") and drops unknown indices.
    public func resolvedSelection(_ selection: Set<Int>?) -> Set<Int> {
        let all = Set(instances)
        return selection.map { $0.intersection(all) } ?? all
    }

    /// A soft mask for the selection at `imageSize`, as a non-color-managed
    /// `CIImage` whose red channel holds coverage in `0...1`.
    public func mask(for selection: Set<Int>?) throws -> CIImage {
        let resolved = resolvedSelection(selection)
        guard !resolved.isEmpty else {
            return CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: imageSize))
        }
        return try makeMask(IndexSet(resolved))
    }

    /// Bounding box of the selection in Core Image pixel coordinates
    /// (bottom-left origin) of the segmented image.
    public func subjectBounds(for selection: Set<Int>?) -> CGRect? {
        labelMap.boundingBox(of: resolvedSelection(selection))
            .map { $0.denormalizedFlipped(to: imageSize) }
    }
}

extension SegmentationResult {
    /// One soft mask covering several objects (a salient-object model's output),
    /// split along `labelMap`'s instances: each object's mask is `mask` gated to
    /// the region nearest that object.
    ///
    /// The regions partition the image and meet in background, so selecting
    /// every object returns `mask` itself, and the per-object masks combine
    /// back into it with `CIMaximumCompositing`.
    public init(imageSize: CGSize, labelMap: LabelMap, splitting mask: CIImage) {
        let instances = labelMap.instances
        let all = IndexSet(instances)
        // A single object is never split, so skip the partition (the common case).
        let regions = instances.count > 1 ? labelMap.nearestInstances() : labelMap
        self.init(imageSize: imageSize, labelMap: labelMap, instances: instances) { selection in
            guard !all.isSubset(of: selection) else { return mask }
            let gate = regions.gate(for: selection, size: imageSize)
            return mask.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: gate])
        }
    }
}

extension LabelMap {
    /// A mask that is 1 on the selected instances and 0 elsewhere, scaled to
    /// `size`. It's data, not color, so it's never color-managed; nearest
    /// sampling keeps it binary. Gray (`L8`), not `R8`, so multiplying by it
    /// gates every channel rather than zeroing green and blue.
    func gate(for selection: IndexSet, size: CGSize) -> CIImage {
        let bytes = Data(labels.map { selection.contains(Int($0)) ? 255 : 0 })
        let small = CIImage(
            bitmapData: bytes,
            bytesPerRow: width,
            size: CGSize(width: width, height: height),
            format: .L8,
            colorSpace: nil
        )
        return small
            .samplingNearest()
            .transformed(by: CGAffineTransform(scaleX: size.width / CGFloat(width), y: size.height / CGFloat(height)))
            .cropped(to: CGRect(origin: .zero, size: size))
    }
}

extension CGRect {
    /// Converts a normalized, top-left-origin rect into pixel coordinates with a
    /// bottom-left origin (Core Image's convention).
    public func denormalizedFlipped(to size: CGSize) -> CGRect {
        CGRect(
            x: minX * size.width,
            y: (1 - maxY) * size.height,
            width: width * size.width,
            height: height * size.height
        )
    }
}
