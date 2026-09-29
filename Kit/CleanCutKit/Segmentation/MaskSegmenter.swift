import CoreGraphics
import CoreImage

/// A segmenter backed by masks that already exist — bundled with the sample
/// photos (so the Simulator, where Vision's instance mask isn't available, still
/// demos the full flow), produced by a Core ML model, or synthesized by tests.
public struct MaskSegmenter: Segmenter {
    public let name: String
    private let masks: [CIImage]
    private let renderer: RenderService

    /// - Parameter masks: One coverage mask per instance (red channel, `0...1`,
    ///   not color-managed), each the size of the image that will be segmented.
    public init(name: String = "Precomputed", masks: [CIImage], renderer: RenderService) {
        self.name = name
        self.masks = masks
        self.renderer = renderer
    }

    public func segment(_ image: CGImage) async throws -> SegmentationResult {
        let size = CGSize(width: image.width, height: image.height)
        let labelMap = try LabelMap(masks: masks, imageSize: size, renderer: renderer)
        let instances = labelMap.instances
        guard !instances.isEmpty else { throw SegmentationError.noSubject }

        let masks = masks
        return SegmentationResult(imageSize: size, labelMap: labelMap, instances: instances) { selection in
            let rect = CGRect(origin: .zero, size: size)
            var sum = CIImage(color: .black).cropped(to: rect)
            for instance in selection where (1...masks.count).contains(instance) {
                sum = masks[instance - 1]
                    .cropped(to: rect)
                    .applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: sum])
            }
            return sum
        }
    }
}

extension LabelMap {
    /// Longest side of label maps built from masks — similar to Vision's.
    static let maxDimension: CGFloat = 512

    /// Builds a label map from per-instance coverage masks: a pixel belongs to
    /// the instance with the highest coverage above 50%.
    init(masks: [CIImage], imageSize: CGSize, renderer: RenderService) throws {
        precondition(masks.count < 256, "too many instances")
        let scale = min(1, Self.maxDimension / max(imageSize.width, imageSize.height))
        let width = max(1, Int((imageSize.width * scale).rounded()))
        let height = max(1, Int((imageSize.height * scale).rounded()))
        let rect = CGRect(x: 0, y: 0, width: width, height: height)

        var labels = [UInt8](repeating: 0, count: width * height)
        var best = [UInt8](repeating: 127, count: width * height)
        for (index, mask) in masks.enumerated() {
            let small = mask
                .resampled(by: CGAffineTransform(scaleX: scale, y: scale))
                .cropped(to: rect)
            var coverage = [UInt8](repeating: 0, count: width * height)
            coverage.withUnsafeMutableBytes { buffer in
                // Rendered rows run top to bottom, matching the label map.
                renderer.context.render(small, toBitmap: buffer.baseAddress!, rowBytes: width, bounds: rect, format: .R8, colorSpace: nil)
            }
            for i in coverage.indices where coverage[i] > best[i] {
                best[i] = coverage[i]
                labels[i] = UInt8(index + 1)
            }
        }
        self.init(width: width, height: height, labels: labels)
    }
}
