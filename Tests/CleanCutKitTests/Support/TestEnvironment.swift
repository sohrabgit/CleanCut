import CoreImage
import Metal
@testable import CleanCutKit

enum TestEnvironment {
    /// Hosted CI runners may have no usable GPU. Tests that need Metal (custom
    /// kernels, GPU timing) are gated on this; everything else runs anywhere.
    static let hasMetal = MTLCreateSystemDefaultDevice() != nil

    static let hasEdgeKernels = hasMetal && EdgeKernels.shared != nil

    static let isSimulator: Bool = {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }()

    /// One shared renderer for the suite; `CIContext` is thread-safe.
    static let renderer = RenderService()
}

/// A synthetic "product photo": a colored rectangle photographed against a
/// colored backdrop, with soft, *contaminated* edges — edge pixels obey the
/// compositing equation `I = α·F + (1 − α)·B`, just like a real camera capture.
struct SyntheticScene {
    let size: CGSize
    let subject: CGRect
    let foreground: RGBA
    let backdrop: RGBA
    let edgeSoftness: CGFloat
    /// Checker square size for a textured product (fine detail); `nil` is plain.
    let texture: CGFloat?

    init(
        size: CGSize = CGSize(width: 400, height: 300),
        subject: CGRect = CGRect(x: 150, y: 90, width: 100, height: 130),
        foreground: RGBA = RGBA(hex: 0xC8321E),
        backdrop: RGBA = RGBA(hex: 0x2FA84F),
        edgeSoftness: CGFloat = 2,
        texture: CGFloat? = nil
    ) {
        self.size = size
        self.subject = subject
        self.foreground = foreground
        self.backdrop = backdrop
        self.edgeSoftness = edgeSoftness
        self.texture = texture
    }

    var extent: CGRect { CGRect(origin: .zero, size: size) }

    /// Soft coverage mask in red, not color-managed.
    var mask: CIImage {
        let hard = CIImage(color: .white).cropped(to: subject)
            .composited(over: CIImage(color: .black))
        guard edgeSoftness > 0 else { return hard.cropped(to: extent) }
        return hard.applyingGaussianBlur(sigma: edgeSoftness).cropped(to: extent)
    }

    var source: CIImage {
        var product = CIImage(color: foreground.ciColor)
        if let texture {
            product = CIFilter(name: "CICheckerboardGenerator", parameters: [
                "inputColor0": foreground.ciColor,
                "inputColor1": foreground.adjustingBrightness(-0.5).ciColor,
                "inputWidth": texture,
            ])!.outputImage!
        }
        return product
            .applyingFilter("CIBlendWithRedMask", parameters: [
                kCIInputBackgroundImageKey: CIImage(color: backdrop.ciColor),
                kCIInputMaskImageKey: mask,
            ])
            .cropped(to: extent)
    }

    var inputs: PipelineInputs {
        PipelineInputs(source: source, mask: mask, subjectBounds: subject)
    }

    /// The same scene at a different resolution.
    func scaled(by factor: CGFloat) -> SyntheticScene {
        SyntheticScene(
            size: CGSize(width: size.width * factor, height: size.height * factor),
            subject: subject.applying(CGAffineTransform(scaleX: factor, y: factor)),
            foreground: foreground,
            backdrop: backdrop,
            edgeSoftness: edgeSoftness * factor,
            texture: texture.map { $0 * factor }
        )
    }
}

extension RGBABitmap {
    /// Peak signal-to-noise ratio over RGB, in dB.
    func psnr(against other: RGBABitmap) -> Double {
        precondition(width == other.width && height == other.height)
        var squaredError = 0.0
        var count = 0
        for i in stride(from: 0, to: bytes.count, by: 4) {
            for c in 0..<3 {
                let d = Double(bytes[i + c]) - Double(other.bytes[i + c])
                squaredError += d * d
            }
            count += 3
        }
        let mse = squaredError / Double(count)
        return mse == 0 ? .infinity : 10 * log10(255 * 255 / mse)
    }

    /// Bounding box (top-left origin) of pixels with alpha above `threshold`.
    func opaqueBounds(threshold: UInt8 = 128) -> CGRect? {
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where self[x, y].a > threshold {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
