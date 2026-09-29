import CoreImage
import Foundation

/// The Core Image kernels in `CaptureKernels.metal`, from the framework's
/// `default.metallib` (the target compiles every `.metal` file as a CIKernel).
public final class CaptureKernels: Sendable {
    /// Loaded once. `nil` only if the Metal library is missing from the bundle.
    public static let shared: CaptureKernels? = try? CaptureKernels()

    private let detailKernel: CIKernel
    private let toneKernel: CIColorKernel

    public init() throws {
        guard let url = Bundle(for: CaptureKernels.self).url(forResource: "default", withExtension: "metallib") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let data = try Data(contentsOf: url)
        detailKernel = try CIKernel(functionName: "subjectDetail", fromMetalLibraryData: data)
        toneKernel = try CIColorKernel(functionName: "subjectTone", fromMetalLibraryData: data)
    }

    /// `(m·lap², m·Y, m·Y², m)` per pixel. `image` must be defined one pixel
    /// beyond `extent` (clamp it), since the Laplacian reads its neighbours.
    func detail(image: CIImage, matte: CIImage, extent: CGRect) -> CIImage? {
        detailKernel.apply(
            extent: extent,
            roiCallback: { index, rect in index == 0 ? rect.insetBy(dx: -1, dy: -1) : rect },
            arguments: [image, matte]
        )
    }

    /// `(m·highlight, m·shadow, m·specular, Y)` per pixel.
    func tone(image: CIImage, matte: CIImage, extent: CGRect) -> CIImage? {
        toneKernel.apply(extent: extent, arguments: [image, matte])
    }
}
