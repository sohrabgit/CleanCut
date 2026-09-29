import CoreImage
import CoreVideo
import Metal

/// Times guided capture's per-frame analysis without a camera: replay frames
/// are pre-rendered into IOSurface-backed BGRA pixel buffers, like the frames
/// `AVCaptureVideoDataOutput` delivers, so generating the scene isn't timed.
///
/// Frames run on the app's schedule: the subject mask is refreshed every
/// `maskInterval` frames and the two statistics kernels run on every frame.
/// Reproducible on any device, unlike pointing a phone at a product.
public struct CaptureBenchmark: Sendable {
    public struct Result: Sendable, Codable, Equatable {
        public var frameSize: CGSize
        public var maskInterval: Int
        /// `FrameAnalyzer.analyze`: downscale, two kernels, reduction, readbacks.
        public var analysisP50MS: Double
        public var analysisP90MS: Double
        /// `CoreMLSegmenter.liveMask`; `nil` when measured without a model.
        public var maskP50MS: Double?
        public var maskP90MS: Double?
        /// One frame as scheduled: analysis, plus the mask on every
        /// `maskInterval`-th frame.
        public var frameP50MS: Double
        public var frameP90MS: Double
        public var frameMeanMS: Double
    }

    /// Guided capture analyzes at most 15 frames a second.
    public static let budgetMS = 1000.0 / 15

    public let frameSize: CGSize
    public let frames: Int
    public let warmupFrames: Int
    public let maskInterval: Int

    public init(frameSize: CGSize = CGSize(width: 1080, height: 1440), frames: Int = 90, warmupFrames: Int = 9, maskInterval: Int) {
        precondition(maskInterval > 0)
        self.frameSize = frameSize
        self.frames = frames
        self.warmupFrames = warmupFrames
        self.maskInterval = maskInterval
    }

    public func run(analyzer: FrameAnalyzer, segmenter: CoreMLSegmenter?) async throws -> Result {
        // One pixel buffer per scenario, rendered once, like camera frames.
        let scene = ReplayScene(size: frameSize)
        let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        var cameraFrames: [CIImage] = []
        for scenario in CaptureScenario.allCases {
            cameraFrames.append(try Self.cameraFrame(scene.frame(scenario), size: frameSize, context: context))
        }

        let clock = ContinuousClock()
        var analysis: [Double] = [], masks: [Double] = [], total: [Double] = []
        var mask: CIImage?
        for index in 0..<(frames + warmupFrames) {
            let frame = cameraFrames[index % cameraFrames.count]
            let start = clock.now
            var maskTime: Double?
            if index % maskInterval == 0, let segmenter {
                mask = try await segmenter.liveMask(for: frame)
                maskTime = (clock.now - start).milliseconds
            }
            let analysisStart = clock.now
            _ = analyzer.analyze(frame, subjectMask: mask)
            let end = clock.now
            guard index >= warmupFrames else { continue }
            analysis.append((end - analysisStart).milliseconds)
            if let maskTime { masks.append(maskTime) }
            total.append((end - start).milliseconds)
        }

        return Result(
            frameSize: frameSize,
            maskInterval: maskInterval,
            analysisP50MS: SegmentationBenchmark.percentile(analysis, 0.5),
            analysisP90MS: SegmentationBenchmark.percentile(analysis, 0.9),
            maskP50MS: masks.isEmpty ? nil : SegmentationBenchmark.percentile(masks, 0.5),
            maskP90MS: masks.isEmpty ? nil : SegmentationBenchmark.percentile(masks, 0.9),
            frameP50MS: SegmentationBenchmark.percentile(total, 0.5),
            frameP90MS: SegmentationBenchmark.percentile(total, 0.9),
            frameMeanMS: total.reduce(0, +) / Double(max(total.count, 1))
        )
    }

    private static func cameraFrame(_ image: CIImage, size: CGSize, context: CIContext) throws -> CIImage {
        var buffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [CFString: Any](),
            kCVPixelBufferMetalCompatibilityKey: true,
        ]
        CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height), kCVPixelFormatType_32BGRA, attributes as CFDictionary, &buffer)
        guard let buffer else { throw BenchmarkError.needsMetal }
        context.render(image, to: buffer, bounds: CGRect(origin: .zero, size: size), colorSpace: nil)
        return CIImage(cvPixelBuffer: buffer, options: [.colorSpace: NSNull()])
    }

    public static func markdown(_ result: Result) -> String {
        func ms(_ value: Double?) -> String { value.map { String(format: "%.1f ms", $0) } ?? "–" }
        let lines = [
            "| Step | p50 | p90 |",
            "|---|---|---|",
            "| Frame statistics (two kernels + GPU reduction) | \(ms(result.analysisP50MS)) | \(ms(result.analysisP90MS)) |",
            "| Subject mask (U²-Netp `liveMask`, 1 frame in \(result.maskInterval)) | \(ms(result.maskP50MS)) | \(ms(result.maskP90MS)) |",
            "| **Per frame, as scheduled** (mean \(ms(result.frameMeanMS))) | **\(ms(result.frameP50MS))** | **\(ms(result.frameP90MS))** |",
        ]
        return lines.joined(separator: "\n") + "\n"
    }
}
