import CoreGraphics
import CoreImage
import Foundation
import Metal

/// Owns the shared, Metal-backed `CIContext`.
///
/// `CIContext` is expensive to create and thread-safe to use, so there is one per
/// process (plus private ones in tests). Working format is half-float linear so
/// blurs and compositing don't band; everything leaving the service is sRGB.
public final class RenderService: Sendable {
    public let context: CIContext
    public let device: (any MTLDevice)?
    public let commandQueue: (any MTLCommandQueue)?

    /// - Parameters:
    ///   - useGPU: Falls back to the software renderer when `false` or when no
    ///     Metal device exists.
    ///   - cacheIntermediates: Keep `true` for interactive editing, where the
    ///     same graph is re-rendered as sliders move; batch work sets it `false`
    ///     so memory doesn't accumulate across unrelated photos.
    ///   - memoryLimitMB: Caps the memory Core Image allocates for render tasks
    ///     (`CIContextOption.memoryTarget`). Without it, the context's texture pool grows
    ///     to well over a gigabyte across a batch of differently sized photos.
    public init(useGPU: Bool = true, cacheIntermediates: Bool = true, memoryLimitMB: Int? = nil) {
        var options: [CIContextOption: Any] = [
            .workingColorSpace: ColorSpaces.linearSRGB,
            .workingFormat: CIFormat.RGBAh,
            .cacheIntermediates: cacheIntermediates,
            .name: "CleanCut",
        ]
        if let memoryLimitMB {
            options[.memoryTarget] = memoryLimitMB
        }
        if useGPU, let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() {
            queue.label = "CleanCut.render"
            self.device = device
            self.commandQueue = queue
            self.context = CIContext(mtlCommandQueue: queue, options: options)
        } else {
            self.device = nil
            self.commandQueue = nil
            self.context = CIContext(options: options.merging([.useSoftwareRenderer: true]) { $1 })
        }
    }

    public var isGPUBacked: Bool { device != nil }

    /// Renders a color image to an 8-bit sRGB `CGImage`.
    public func makeCGImage(_ image: CIImage, rect: CGRect? = nil, format: CIFormat = .RGBA8) -> CGImage? {
        context.createCGImage(image, from: rect ?? image.extent, format: format, colorSpace: ColorSpaces.sRGB)
    }

    /// Renders a mask (coverage in red) to an 8-bit single-channel `CGImage`
    /// without color management, so coverage values survive exactly.
    public func makeMaskImage(_ mask: CIImage, rect: CGRect? = nil) -> CGImage? {
        let rect = (rect ?? mask.extent).integral
        let width = Int(rect.width), height = Int(rect.height)
        guard width > 0, height > 0 else { return nil }
        // `createCGImage` refuses single-channel output without a color space, so
        // render the raw bytes ourselves. The gray color space is only a label:
        // masks are always read back with color management disabled.
        var bytes = Data(count: width * height)
        bytes.withUnsafeMutableBytes { buffer in
            context.render(mask, toBitmap: buffer.baseAddress!, rowBytes: width, bounds: rect, format: .R8, colorSpace: nil)
        }
        guard let provider = CGDataProvider(data: bytes as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }

    /// Renders an image into a tightly-packed RGBA8 sRGB buffer. Used by tests and
    /// analysis code that needs exact pixel values.
    public func rgbaPixels(_ image: CIImage, rect: CGRect? = nil) -> RGBABitmap {
        let rect = (rect ?? image.extent).integral
        let width = Int(rect.width), height = Int(rect.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            context.render(
                image,
                toBitmap: buffer.baseAddress!,
                rowBytes: width * 4,
                bounds: rect,
                format: .RGBA8,
                colorSpace: ColorSpaces.sRGB
            )
        }
        return RGBABitmap(width: width, height: height, bytes: bytes)
    }
}

/// A tightly-packed RGBA8 buffer with a **top-left** origin (row 0 is the top).
public struct RGBABitmap: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public let bytes: [UInt8]

    public struct Pixel: Equatable, Sendable, CustomStringConvertible {
        public let r, g, b, a: UInt8
        public var description: String { "(\(r), \(g), \(b), \(a))" }
    }

    public subscript(x: Int, y: Int) -> Pixel {
        let i = (y * width + x) * 4
        return Pixel(r: bytes[i], g: bytes[i + 1], b: bytes[i + 2], a: bytes[i + 3])
    }
}
