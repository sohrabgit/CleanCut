import CoreGraphics
import CoreImage
import CoreML
import Vision

/// Salient-object segmentation with a converted open-source Core ML model
/// (U²-Netp or ISNet, see Tools/ModelConversion).
///
/// The models output one soft mask for "the salient object", so there are no
/// instances to tap: the result always has a single instance.
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
        let labelMap = try LabelMap(masks: [mask], imageSize: size, renderer: renderer)
        guard !labelMap.instances.isEmpty else { throw SegmentationError.noSubject }
        let result = SegmentationResult(imageSize: size, labelMap: labelMap, instances: [1]) { _ in mask }
        let postprocess = clock.now - start

        return (result, Timings(preprocess: preprocess, inference: inference, postprocess: postprocess))
    }

    /// Owns the (non-`Sendable`) `MLModel`; predictions are serialized per model.
    private actor Engine {
        let model: MLModel
        let constraint: MLImageConstraint

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
