import CoreGraphics
import CoreImage

/// A photo that has been decoded, segmented, and turned into a small preview
/// proxy — everything the editor needs to render frames cheaply.
///
/// - The **working image** (≤ 4096 px) feeds exports.
/// - The **proxy** (≤ 1600 px) feeds the live preview. Its source and
///   per-instance masks are rendered to bitmaps once, so a preview frame never
///   re-decodes, re-segments or re-samples a full-size image. Toggling an
///   instance just sums different cached masks.
public struct PreparedPhoto: Sendable {
    public let workingImage: CGImage
    public let segmentation: SegmentationResult
    public let proxySource: CIImage
    /// Proxy pixels per working-image pixel.
    public let proxyScale: CGFloat
    /// One bitmap-backed mask per instance, at proxy size (coverage in red).
    public let proxyMasks: [Int: CIImage]

    public static let proxyMaxDimension: CGFloat = 1600

    public var instances: [Int] { segmentation.instances }

    /// The engine that produced the masks, e.g. "Vision" or "U²-Netp".
    public var segmenterName: String = ""

    public static func prepare(
        _ image: CGImage,
        segmenter: any Segmenter,
        renderer: RenderService
    ) async throws -> PreparedPhoto {
        let segmentation = try await segmenter.segment(image)
        var photo = try prepare(image, segmentation: segmentation, renderer: renderer)
        photo.segmenterName = (segmenter as? FallbackSegmenter)?.lastUsedName ?? segmenter.name
        return photo
    }

    /// Builds the proxy for an image that has already been segmented.
    public static func prepare(
        _ image: CGImage,
        segmentation: SegmentationResult,
        renderer: RenderService
    ) throws -> PreparedPhoto {
        let longSide = CGFloat(max(image.width, image.height))
        let scale = min(1, proxyMaxDimension / longSide)
        let toProxy = CGAffineTransform(scaleX: scale, y: scale)
        let proxyRect = CGRect(
            x: 0, y: 0,
            width: (CGFloat(image.width) * scale).rounded(),
            height: (CGFloat(image.height) * scale).rounded()
        )

        let source = CIImage(cgImage: image)
            .resampled(by: toProxy)
            .cropped(to: proxyRect)
        guard let proxyCG = renderer.makeCGImage(source, rect: proxyRect) else {
            throw SegmentationError.failed("Could not render preview")
        }

        var masks: [Int: CIImage] = [:]
        for instance in segmentation.instances {
            let mask = try segmentation.mask(for: [instance])
                .resampled(by: toProxy)
                .cropped(to: proxyRect)
            guard let maskCG = renderer.makeMaskImage(mask, rect: proxyRect) else {
                throw SegmentationError.failed("Could not render mask")
            }
            masks[instance] = CIImage(cgImage: maskCG, options: [.colorSpace: NSNull()])
        }

        return PreparedPhoto(
            workingImage: image,
            segmentation: segmentation,
            proxySource: CIImage(cgImage: proxyCG),
            proxyScale: scale,
            proxyMasks: masks
        )
    }

    /// Combined proxy mask for a selection: the per-pixel maximum of the
    /// selected instances' coverage. (Additive compositing would also add the
    /// opaque alpha channels, and unpremultiplying alpha 2 halves the coverage.)
    public func proxyMask(for selection: Set<Int>?) -> CIImage {
        let selected = segmentation.resolvedSelection(selection).sorted()
        let empty = CIImage(color: .black).cropped(to: proxySource.extent)
        return selected.compactMap { proxyMasks[$0] }.reduce(empty) { sum, mask in
            mask.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: sum])
        }
    }

    /// Pipeline inputs for the live preview, or `nil` if nothing is selected.
    public func previewInputs(selection: Set<Int>?) -> PipelineInputs? {
        guard let bounds = segmentation.subjectBounds(for: selection) else { return nil }
        return PipelineInputs(
            source: proxySource,
            mask: proxyMask(for: selection),
            subjectBounds: bounds.applying(CGAffineTransform(scaleX: proxyScale, y: proxyScale))
        )
    }

    /// Full-quality pipeline inputs for export, or `nil` if nothing is selected.
    public func exportInputs(selection: Set<Int>?) throws -> PipelineInputs? {
        guard let bounds = segmentation.subjectBounds(for: selection) else { return nil }
        return PipelineInputs(
            source: CIImage(cgImage: workingImage),
            mask: try segmentation.mask(for: selection),
            subjectBounds: bounds
        )
    }
}
