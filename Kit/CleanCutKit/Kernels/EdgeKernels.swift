import CoreImage
import Foundation

/// Custom Core Image kernels compiled from `EdgeDecontamination.metal`.
///
/// The target builds its Metal sources with `-fcikernel` / `-cikernel`
/// (see project.yml), producing a `default.metallib` inside the framework bundle.
public final class EdgeKernels: Sendable {
    /// Loaded once. `nil` only if the Metal library is missing from the bundle,
    /// in which case the pipeline renders without edge cleanup.
    public static let shared: EdgeKernels? = try? EdgeKernels()

    private let decontaminateKernel: CIColorKernel

    public init() throws {
        guard let url = Bundle(for: BundleToken.self).url(forResource: "default", withExtension: "metallib") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let data = try Data(contentsOf: url)
        decontaminateKernel = try CIColorKernel(functionName: "decontaminateEdges", fromMetalLibraryData: data)
    }

    /// Removes backdrop color from the matte's soft edge.
    ///
    /// - Parameters:
    ///   - image: The opaque source photo.
    ///   - matte: Canonical matte (coverage in red), same extent as `image`.
    ///   - strength: `0...1`, how much of the estimated contamination to remove.
    ///   - backgroundRadius: Blur radius (px) for the local backdrop estimate. It
    ///     must be wide enough to reach from the edge band into clean backdrop.
    public func decontaminate(image: CIImage, matte: CIImage, strength: Double, backgroundRadius: CGFloat) -> CIImage {
        let extent = image.extent
        // Weight w = (1 − α)⁴: mixed edge pixels still contain product color, so
        // they must count far less than clean backdrop when estimating B.
        let backdropWeight = matte
            .applyingFilter("CIColorInvert")
            .applyingFilter("CIGammaAdjust", parameters: ["inputPower": 4])
        // Backdrop-only pixels, premultiplied by w, then spread inward.
        let backdrop = image
            .applyingFilter("CIBlendWithRedMask", parameters: [
                kCIInputBackgroundImageKey: CIImage.empty(),
                kCIInputMaskImageKey: backdropWeight,
            ])
            .applyingGaussianBlur(sigma: backgroundRadius)
            .cropped(to: extent)

        return decontaminateKernel.apply(
            extent: extent,
            arguments: [image, backdrop, matte, Float(strength)]
        ) ?? image
    }
}

private final class BundleToken {}
