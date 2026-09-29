import CoreImage
import Metal

/// What one camera frame looks like to the capture coach. Fractions are of the
/// subject's area unless noted; tone values are camera-encoded (`0...1`).
public struct FrameMetrics: Sendable, Equatable {
    /// Laplacian energy relative to the subject's own luma variance. Blur kills
    /// fine detail much faster than overall contrast, so the ratio drops sharply
    /// with blur while staying comparable between busy and plain products.
    public var sharpness: Double
    /// Mean luma of the subject.
    public var subjectLuma: Double
    /// Mean luma of the whole frame, subject or not.
    public var frameLuma: Double
    /// Share of the subject with a blown channel.
    public var highlightClip: Double
    /// Share of the subject crushed to black.
    public var shadowClip: Double
    /// Share of the subject that is clipped near-white: specular reflections.
    public var specular: Double
    /// The subject's bounding box, normalized to the frame with a **top-left**
    /// origin (ready for an overlay). `nil` when there is no subject.
    public var subjectBounds: CGRect?
    /// Share of the frame the subject covers.
    public var subjectCoverage: Double

    public init(
        sharpness: Double = 0,
        subjectLuma: Double = 0,
        frameLuma: Double = 0,
        highlightClip: Double = 0,
        shadowClip: Double = 0,
        specular: Double = 0,
        subjectBounds: CGRect? = nil,
        subjectCoverage: Double = 0
    ) {
        self.sharpness = sharpness
        self.subjectLuma = subjectLuma
        self.frameLuma = frameLuma
        self.highlightClip = highlightClip
        self.shadowClip = shadowClip
        self.specular = specular
        self.subjectBounds = subjectBounds
        self.subjectCoverage = subjectCoverage
    }
}

/// Measures a live camera frame on the GPU: two custom kernels, reduced with
/// `CIAreaAverage` and read back as eight floats, plus a tiny mask readback for
/// framing.
///
/// Owns a context that isn't color-managed: clipping thresholds only mean
/// something in the camera's encoded values, where the sensor clips. Make one
/// per capture session, like `RenderService` per editor session
/// (docs/DECISIONS.md, 006).
public final class FrameAnalyzer: Sendable {
    /// Frames are measured at this short side (or smaller if the frame is), so
    /// the sharpness score doesn't depend on the camera's resolution.
    public static let analysisShortSide: CGFloat = 720
    /// Long side of the mask readback used for the subject's bounding box.
    static let boundsLongSide: CGFloat = 128

    private let context: CIContext
    private let kernels: CaptureKernels

    public init(device: (any MTLDevice)? = MTLCreateSystemDefaultDevice()) throws {
        guard let kernels = CaptureKernels.shared else { throw CocoaError(.fileNoSuchFile) }
        self.kernels = kernels
        let options: [CIContextOption: Any] = [
            .workingColorSpace: NSNull(),
            .outputColorSpace: NSNull(),
            .workingFormat: CIFormat.RGBAf,
            .cacheIntermediates: false,
            .name: "CleanCut.capture",
        ]
        if let device {
            context = CIContext(mtlDevice: device, options: options)
        } else {
            context = CIContext(options: options.merging([.useSoftwareRenderer: true]) { $1 })
        }
    }

    /// - Parameters:
    ///   - frame: The upright camera frame.
    ///   - subjectMask: Coverage in red, any resolution; it is stretched over the
    ///     frame. `nil` measures the whole frame and reports no subject.
    public func analyze(_ frame: CIImage, subjectMask: CIImage?) -> FrameMetrics {
        let extent = frame.extent
        guard !extent.isInfinite, extent.width >= 2, extent.height >= 2 else { return FrameMetrics() }

        let scale = min(1, Self.analysisShortSide / min(extent.width, extent.height))
        let rect = CGRect(x: 0, y: 0, width: (extent.width * scale).rounded(.down), height: (extent.height * scale).rounded(.down))
        let image = frame.resampled(by: Self.transform(from: extent, to: rect))

        let matte = subjectMask.map { mask in
            Matte.canonical(mask.resampled(by: Self.transform(from: mask.extent, to: rect)))
        } ?? CIImage(color: .white)

        var metrics = FrameMetrics()
        if let stats = statistics(image: image, matte: matte, rect: rect) {
            let weight = max(Double(stats.detail.w), 1e-6)
            let mean = Double(stats.detail.y) / weight
            let variance = max(Double(stats.detail.z) / weight - mean * mean, 0)
            metrics.sharpness = Double(stats.detail.x) / weight / (variance + 1e-4)
            metrics.subjectLuma = mean
            metrics.highlightClip = Double(stats.tone.x) / weight
            metrics.shadowClip = Double(stats.tone.y) / weight
            metrics.specular = Double(stats.tone.z) / weight
            metrics.frameLuma = Double(stats.tone.w)
        }
        if subjectMask != nil {
            (metrics.subjectBounds, metrics.subjectCoverage) = subjectBounds(matte: matte, rect: rect)
        }
        return metrics
    }

    // MARK: - GPU

    /// Both kernels' frame-wide means in one render: two `CIAreaAverage` pixels
    /// side by side, read back as `RGBAf`.
    private func statistics(image: CIImage, matte: CIImage, rect: CGRect) -> (detail: SIMD4<Float>, tone: SIMD4<Float>)? {
        guard let detail = kernels.detail(image: image.clampedToExtent(), matte: matte, extent: rect),
              let tone = kernels.tone(image: image, matte: matte, extent: rect)
        else { return nil }

        func average(_ image: CIImage, at x: CGFloat) -> CIImage {
            let pixel = image.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: rect)])
            return pixel.transformed(by: CGAffineTransform(translationX: x - pixel.extent.minX, y: -pixel.extent.minY))
        }
        // The two 1×1 pixels don't overlap, so `over` just places them.
        let pair = average(detail, at: 0).composited(over: average(tone, at: 1))

        var values = [Float](repeating: 0, count: 8)
        values.withUnsafeMutableBytes { buffer in
            context.render(pair, toBitmap: buffer.baseAddress!, rowBytes: 8 * MemoryLayout<Float>.size,
                           bounds: CGRect(x: 0, y: 0, width: 2, height: 1), format: .RGBAf, colorSpace: nil)
        }
        return (SIMD4(values[0], values[1], values[2], values[3]), SIMD4(values[4], values[5], values[6], values[7]))
    }

    /// The subject's box and coverage from a ≤128-px readback of the matte
    /// (threshold 0.5). Rows come back top first, hence the top-left origin.
    private func subjectBounds(matte: CIImage, rect: CGRect) -> (CGRect?, Double) {
        let scale = Self.boundsLongSide / max(rect.width, rect.height)
        let width = max(1, Int((rect.width * scale).rounded())), height = max(1, Int((rect.height * scale).rounded()))
        let small = matte.cropped(to: rect).resampled(by: CGAffineTransform(
            scaleX: CGFloat(width) / rect.width, y: CGFloat(height) / rect.height))

        var bytes = [UInt8](repeating: 0, count: width * height)
        bytes.withUnsafeMutableBytes { buffer in
            context.render(small, toBitmap: buffer.baseAddress!, rowBytes: width,
                           bounds: CGRect(x: 0, y: 0, width: width, height: height), format: .R8, colorSpace: nil)
        }

        var minX = width, minY = height, maxX = -1, maxY = -1, count = 0
        for y in 0..<height {
            for x in 0..<width where bytes[y * width + x] >= 128 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
                count += 1
            }
        }
        guard maxX >= 0 else { return (nil, 0) }
        let bounds = CGRect(
            x: Double(minX) / Double(width), y: Double(minY) / Double(height),
            width: Double(maxX - minX + 1) / Double(width), height: Double(maxY - minY + 1) / Double(height)
        )
        return (bounds, Double(count) / Double(width * height))
    }

    /// Maps `source` onto `target`, stretching if the aspect ratios differ.
    private static func transform(from source: CGRect, to target: CGRect) -> CGAffineTransform {
        CGAffineTransform(translationX: -source.minX, y: -source.minY)
            .concatenating(CGAffineTransform(scaleX: target.width / source.width, y: target.height / source.height))
            .concatenating(CGAffineTransform(translationX: target.minX, y: target.minY))
    }
}
