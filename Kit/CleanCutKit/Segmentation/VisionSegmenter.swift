import CoreGraphics
import CoreImage
import CoreML
import Vision

/// Foreground instance segmentation with Vision
/// (`GenerateForegroundInstanceMaskRequest`, iOS 18 / macOS 15 Swift API).
public struct VisionSegmenter: Segmenter {
    /// Forces the compute device for the main inference stage; `nil` lets Vision
    /// decide. Used by the benchmark to compare CPU / GPU / Neural Engine.
    public var computeDevice: MLComputeDevice?

    public init(computeDevice: MLComputeDevice? = nil) {
        self.computeDevice = computeDevice
    }

    /// Every compute device on this machine. Devices the request can't use
    /// fail at `segment` time and show up as "unsupported" in benchmarks.
    public static var supportedComputeDevices: [MLComputeDevice] {
        MLComputeDevice.allComputeDevices
    }

    public var name: String {
        guard let computeDevice else { return "Vision" }
        return "Vision (\(computeDevice.shortName))"
    }

    public func segment(_ image: CGImage) async throws -> SegmentationResult {
        var request = GenerateForegroundInstanceMaskRequest()
        if let computeDevice {
            request.setComputeDevice(computeDevice, for: .main)
        }
        let handler = ImageRequestHandler(image)

        let observation: InstanceMaskObservation?
        do {
            observation = try await handler.perform(request)
        } catch {
            #if targetEnvironment(simulator)
            throw SegmentationError.unavailable("Vision foreground masks need a real device or a Mac.")
            #else
            throw SegmentationError.failed(String(describing: error))
            #endif
        }
        guard let observation, !observation.allInstances.isEmpty else {
            throw SegmentationError.noSubject
        }

        let labelMap = try LabelMap(labelImage: observation.allInstancesMask.cgImage)
        return SegmentationResult(
            imageSize: CGSize(width: image.width, height: image.height),
            labelMap: labelMap,
            instances: observation.allInstances.sorted()
        ) { instances in
            let buffer = try observation.generateScaledMask(for: instances, scaledToImageFrom: handler)
            // Masks are data, not color: never color-manage them.
            return CIImage(cvPixelBuffer: buffer, options: [.colorSpace: NSNull()])
        }
    }
}

extension LabelMap {
    /// Reads an instance label image byte-for-byte (no color conversion, which
    /// would corrupt label values). Vision hands the 8-bit label buffer back as
    /// either 8-bit gray or 32-bit RGB with the label replicated per channel.
    init(labelImage image: CGImage) throws {
        guard image.bitsPerComponent == 8,
              image.bitsPerPixel == 8 || image.bitsPerPixel == 32,
              let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data)
        else {
            throw SegmentationError.failed("Unexpected instance mask format")
        }
        let width = image.width, height = image.height, rowBytes = image.bytesPerRow
        let stride = image.bitsPerPixel / 8
        // In every 32-bit layout (RGBX, XRGB and their byte-swapped forms),
        // byte 1 is a color channel, never the padding byte.
        let offset = stride == 4 ? 1 : 0
        var labels = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            let row = bytes + y * rowBytes
            for x in 0..<width {
                labels[y * width + x] = row[x * stride + offset]
            }
        }
        self.init(width: width, height: height, labels: labels)
    }
}

extension MLComputeDevice {
    public var shortName: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .neuralEngine: "ANE"
        @unknown default: "Other"
        }
    }
}
