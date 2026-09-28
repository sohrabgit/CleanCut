import CoreGraphics
import CoreImage
import CoreML
import Vision

/// Salient-object segmentation with a converted open-source Core ML model
/// (U²-Netp or ISNet, see Tools/ModelConversion).
///
/// The models output one soft mask for everything salient, so the mask is
/// split into its disconnected objects (`LabelMap.separatingObjects`) to keep
/// tap-to-select working where Vision can't run.
public struct CoreMLSegmenter: Segmenter {
    /// Time spent in each stage of the last `segmentWithTimings` call.
    public struct Timings: Sendable {
        public var preprocess: Duration
        public var inference: Duration
        public var postprocess: Duration
    }

    public let name: String
    public let computeUnits: MLComputeUnits
    private let engine: Engine
    private let renderer: RenderService

    /// Loads a compiled model (`.mlmodelc`).
    public init(compiledModelAt url: URL, name: String, computeUnits: MLComputeUnits = .all, renderer: RenderService) throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        self.engine = try Engine(model: MLModel(contentsOf: url, configuration: configuration))
        self.name = name
        self.computeUnits = computeUnits
        self.renderer = renderer
    }

    /// Compiles an `.mlpackage` to a temporary `.mlmodelc`.
    public static func compile(_ packageURL: URL) async throws -> URL {
        try await MLModel.compileModel(at: packageURL)
    }

    public func segment(_ image: CGImage) async throws -> SegmentationResult {
        try await segmentWithTimings(image).result
    }

    public func segmentWithTimings(_ image: CGImage) async throws -> (result: SegmentationResult, timings: Timings) {
        let clock = ContinuousClock()
        let size = CGSize(width: image.width, height: image.height)

        let (lowResMask, preprocess, inference) = try await engine.predict(image)

        let start = clock.now
        // The model saw the image stretched to a square; stretch the mask back.
        let scale = CGAffineTransform(
            scaleX: size.width / lowResMask.extent.width,
            y: size.height / lowResMask.extent.height
        )
        let mask = lowResMask.resampled(by: scale).cropped(to: CGRect(origin: .zero, size: size))
        let labelMap = try LabelMap(masks: [mask], imageSize: size, renderer: renderer).separatingObjects()
        guard !labelMap.instances.isEmpty else { throw SegmentationError.noSubject }
        let result = SegmentationResult(imageSize: size, labelMap: labelMap, splitting: mask)
        let postprocess = clock.now - start

        return (result, Timings(preprocess: preprocess, inference: inference, postprocess: postprocess))
    }

    /// A coarse subject mask for a live camera frame (coverage in red, not
    /// color-managed), stretched over the frame's extent.
    ///
    /// Skips everything `segment` does after inference (label map, splitting into
    /// objects): guided capture only needs where the product is, several times a
    /// second, and takes frames straight from the camera rather than `CGImage`s.
    public func liveMask(for frame: CIImage) async throws -> CIImage {
        let lowResMask = try await engine.predict(frame, context: renderer.context)
        let extent = frame.extent
        let toFrame = CGAffineTransform(scaleX: extent.width / lowResMask.extent.width, y: extent.height / lowResMask.extent.height)
            .concatenating(CGAffineTransform(translationX: extent.minX, y: extent.minY))
        return lowResMask.resampled(by: toFrame)
    }

    /// Owns the (non-`Sendable`) `MLModel`; predictions are serialized per model.
    private actor Engine {
        let model: MLModel
        let constraint: MLImageConstraint
        /// Input buffers for `liveMask`, recycled across frames.
        private var inputPool: CVPixelBufferPool?

        init(model: MLModel) throws {
            guard let constraint = model.modelDescription.inputDescriptionsByName["image"]?.imageConstraint else {
                throw SegmentationError.failed("Model has no image input named 'image'")
            }
            self.model = model
            self.constraint = constraint
        }

        func predict(_ image: CGImage) throws -> (mask: CIImage, preprocess: Duration, inference: Duration) {
            let clock = ContinuousClock()
            var start = clock.now
            let input = try MLFeatureValue(
                cgImage: image,
                constraint: constraint,
                options: [.cropAndScale: VNImageCropAndScaleOption.scaleFill.rawValue]
            )
            let provider = try MLDictionaryFeatureProvider(dictionary: ["image": input])
            let preprocess = clock.now - start

            start = clock.now
            let output = try model.prediction(from: provider)
            guard let buffer = output.featureValue(for: "mask")?.imageBufferValue else {
                throw SegmentationError.failed("Model has no image output named 'mask'")
            }
            let inference = clock.now - start
            return (CIImage(cvPixelBuffer: buffer, options: [.colorSpace: NSNull()]), preprocess, inference)
        }

        /// Renders `frame` stretched into a pooled model-sized buffer (the
        /// `scaleFill` the model was trained with) and predicts on it. The
        /// buffer never leaves the actor.
        func predict(_ frame: CIImage, context: CIContext) throws -> CIImage {
            let width = constraint.pixelsWide, height = constraint.pixelsHigh
            let input = try makeInputBuffer(width: width, height: height)
            let extent = frame.extent
            let fitted = frame.resampled(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY)
                .concatenating(CGAffineTransform(scaleX: CGFloat(width) / extent.width, y: CGFloat(height) / extent.height)))
            context.render(fitted, to: input, bounds: CGRect(x: 0, y: 0, width: width, height: height), colorSpace: ColorSpaces.sRGB)

            let provider = try MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(pixelBuffer: input)])
            guard let mask = try model.prediction(from: provider).featureValue(for: "mask")?.imageBufferValue else {
                throw SegmentationError.failed("Model has no image output named 'mask'")
            }
            return CIImage(cvPixelBuffer: mask, options: [.colorSpace: NSNull()])
        }

        private func makeInputBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
            if inputPool == nil {
                let attributes: [CFString: Any] = [
                    kCVPixelBufferPixelFormatTypeKey: constraint.pixelFormatType,
                    kCVPixelBufferWidthKey: width,
                    kCVPixelBufferHeightKey: height,
                    kCVPixelBufferIOSurfacePropertiesKey: [CFString: Any](),
                    kCVPixelBufferMetalCompatibilityKey: true,
                ]
                CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &inputPool)
            }
            var buffer: CVPixelBuffer?
            guard let inputPool, CVPixelBufferPoolCreatePixelBuffer(nil, inputPool, &buffer) == kCVReturnSuccess, let buffer else {
                throw SegmentationError.failed("Couldn't allocate a model input buffer")
            }
            return buffer
        }
    }
}

extension MLComputeUnits {
    public var shortName: String {
        switch self {
        case .cpuOnly: "CPU"
        case .cpuAndGPU: "CPU+GPU"
        case .cpuAndNeuralEngine: "CPU+ANE"
        case .all: "All"
        @unknown default: "Other"
        }
    }
}
