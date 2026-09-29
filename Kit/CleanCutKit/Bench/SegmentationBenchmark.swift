import CoreGraphics
import CoreML
import Foundation

/// One engine + compute-unit combination to measure.
public struct BenchmarkConfiguration: Sendable {
    public let engine: String
    public let compute: String
    public let modelSizeMB: Double?
    public let loadsLazily: Bool
    /// Builds the segmenter; the time this takes is reported as "load".
    public let makeSegmenter: @Sendable () async throws -> any Segmenter

    public init(
        engine: String,
        compute: String,
        modelSizeMB: Double?,
        loadsLazily: Bool = false,
        makeSegmenter: @escaping @Sendable () async throws -> any Segmenter
    ) {
        self.engine = engine
        self.compute = compute
        self.modelSizeMB = modelSizeMB
        self.loadsLazily = loadsLazily
        self.makeSegmenter = makeSegmenter
    }
}

extension BenchmarkConfiguration {
    /// Vision with automatic placement (the reference for agreement), then
    /// pinned to each compute device it supports here.
    public static var vision: [BenchmarkConfiguration] {
        var configurations = [BenchmarkConfiguration(engine: "Vision", compute: "Auto", modelSizeMB: nil, loadsLazily: true) { VisionSegmenter() }]
        for device in VisionSegmenter.supportedComputeDevices {
            configurations.append(BenchmarkConfiguration(engine: "Vision", compute: device.shortName, modelSizeMB: nil, loadsLazily: true) {
                VisionSegmenter(computeDevice: device)
            })
        }
        return configurations
    }

    /// A compiled model on each set of compute units. Pass a stable location
    /// (the app bundle, or a cache): the OS keys its Neural Engine compile
    /// cache on it.
    public static func coreML(compiledModelAt url: URL, name: String, sizeMB: Double?, renderer: RenderService) -> [BenchmarkConfiguration] {
        [MLComputeUnits.cpuOnly, .cpuAndGPU, .cpuAndNeuralEngine, .all].map { units in
            BenchmarkConfiguration(engine: name, compute: units.shortName, modelSizeMB: sizeMB) {
                try CoreMLSegmenter(compiledModelAt: url, name: name, computeUnits: units, renderer: renderer)
            }
        }
    }

    /// Vision's automatic configuration: every other row is compared with it.
    public var isReference: Bool { engine == "Vision" && compute == "Auto" }
}

public struct BenchmarkResult: Sendable, Codable {
    public var engine: String
    public var compute: String
    public var modelSizeMB: Double?
    /// First load in this process. For Core ML on the Neural Engine this
    /// includes the one-time on-device compile, which the OS then caches.
    public var loadMS: Double
    /// A second load of the same model, served from the system's caches.
    public var reloadMS: Double
    /// `true` when the engine loads lazily inside its first run (Vision).
    public var loadsLazily: Bool
    public var firstRunMS: Double
    /// Model inference only (Vision: the whole request — it's a black box).
    public var inferenceP50MS: Double
    public var inferenceP90MS: Double
    /// Decoded image in → full-resolution mask + label map out.
    public var endToEndP50MS: Double
    /// Mean IoU of the foreground against Vision's mask (1 = identical).
    public var meanIoUVsVision: Double?
    public var peakMemoryMB: Double
    public var failures: Int
    public var error: String?
}

/// Measures segmentation engines on a fixed set of photos.
public struct SegmentationBenchmark: Sendable {
    public let images: [CGImage]
    public let warmupRuns: Int
    public let measuredRuns: Int

    public init(images: [CGImage], warmupRuns: Int = 5, measuredRuns: Int = 30) {
        precondition(!images.isEmpty, "benchmark needs photos")
        self.images = images
        self.warmupRuns = warmupRuns
        self.measuredRuns = measuredRuns
    }

    /// Runs one configuration. `reference` holds Vision's label maps, one per
    /// image, for the agreement metric.
    public func run(_ configuration: BenchmarkConfiguration, reference: [LabelMap]? = nil) async -> BenchmarkResult {
        let clock = ContinuousClock()
        var result = BenchmarkResult(
            engine: configuration.engine, compute: configuration.compute, modelSizeMB: configuration.modelSizeMB,
            loadMS: 0, reloadMS: 0, loadsLazily: configuration.loadsLazily, firstRunMS: 0, inferenceP50MS: 0, inferenceP90MS: 0, endToEndP50MS: 0,
            meanIoUVsVision: nil, peakMemoryMB: 0, failures: 0
        )
        let sampler = PeakMemorySampler()
        let baseline = MemoryProbe.footprint()
        sampler.start()

        do {
            var start = clock.now
            _ = try await configuration.makeSegmenter()
            result.loadMS = (clock.now - start).milliseconds

            start = clock.now
            let segmenter = try await configuration.makeSegmenter()
            result.reloadMS = (clock.now - start).milliseconds

            start = clock.now
            _ = try await segmenter.segment(images[0])
            result.firstRunMS = (clock.now - start).milliseconds

            for index in 0..<warmupRuns {
                _ = try? await segmenter.segment(images[index % images.count])
            }

            var inference: [Double] = []
            var endToEnd: [Double] = []
            for index in 0..<measuredRuns {
                let image = images[index % images.count]
                let runStart = clock.now
                do {
                    if let coreML = segmenter as? CoreMLSegmenter {
                        let (_, timings) = try await coreML.segmentWithTimings(image)
                        inference.append(timings.inference.milliseconds)
                    } else {
                        _ = try await segmenter.segment(image)
                        inference.append((clock.now - runStart).milliseconds)
                    }
                    endToEnd.append((clock.now - runStart).milliseconds)
                } catch {
                    result.failures += 1
                }
            }
            result.inferenceP50MS = Self.percentile(inference, 0.5)
            result.inferenceP90MS = Self.percentile(inference, 0.9)
            result.endToEndP50MS = Self.percentile(endToEnd, 0.5)

            if let reference {
                var scores: [Double] = []
                for (image, expected) in zip(images, reference) {
                    guard let map = try? await segmenter.segment(image).labelMap else { continue }
                    scores.append(Self.foregroundIoU(map, expected))
                }
                result.meanIoUVsVision = scores.isEmpty ? nil : scores.reduce(0, +) / Double(scores.count)
            }
        } catch {
            result.error = String(describing: error)
        }
        let peak = sampler.stop()
        result.peakMemoryMB = Double(peak > baseline ? peak - baseline : 0) / 1_048_576
        return result
    }

    /// Nearest-rank percentile of a sample.
    public static func percentile(_ values: [Double], _ p: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let rank = Int((p * Double(sorted.count)).rounded(.up)) - 1
        return sorted[min(max(rank, 0), sorted.count - 1)]
    }

    /// IoU of "any instance" between two label maps of possibly different
    /// resolutions, sampled on a shared normalized grid.
    public static func foregroundIoU(_ a: LabelMap, _ b: LabelMap, grid: Int = 256) -> Double {
        var intersection = 0, union = 0
        for y in 0..<grid {
            for x in 0..<grid {
                let point = CGPoint(x: (Double(x) + 0.5) / Double(grid), y: (Double(y) + 0.5) / Double(grid))
                let inA = (a.label(atNormalized: point) ?? 0) != 0
                let inB = (b.label(atNormalized: point) ?? 0) != 0
                if inA && inB { intersection += 1 }
                if inA || inB { union += 1 }
            }
        }
        return union == 0 ? 1 : Double(intersection) / Double(union)
    }
}

extension Duration {
    public var milliseconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) * 1000 + Double(attoseconds) / 1e15
    }
}

public enum BenchmarkReport {
    public static func markdown(_ results: [BenchmarkResult], imageCount: Int, machine: String) -> String {
        func ms(_ value: Double) -> String { value >= 100 ? String(format: "%.0f", value) : String(format: "%.1f", value) }
        var lines = [
            "| Engine | Compute units | Size | Load | Reload | First run | Inference p50 | p90 | End-to-end p50 | IoU vs Vision | Peak mem |",
            "|---|---|---|---|---|---|---|---|---|---|---|",
        ]
        for r in results {
            guard r.error == nil else {
                lines.append("| \(r.engine) | \(r.compute) | – | – | – | – | unsupported | – | – | – | – |")
                continue
            }
            let size = r.modelSizeMB.map { String(format: "%.1f MB", $0) } ?? "system"
            let iou = r.meanIoUVsVision.map { String(format: "%.3f", $0) } ?? "ref."
            let load = r.loadsLazily ? "lazy" : "\(ms(r.loadMS)) ms"
            let reload = r.loadsLazily ? "lazy" : "\(ms(r.reloadMS)) ms"
            lines.append(
                "| \(r.engine) | \(r.compute) | \(size) | \(load) | \(reload) | \(ms(r.firstRunMS)) ms | **\(ms(r.inferenceP50MS)) ms** | \(ms(r.inferenceP90MS)) ms | \(ms(r.endToEndP50MS)) ms | \(iou) | \(String(format: "%.0f", r.peakMemoryMB)) MB |"
            )
        }
        lines.append("")
        lines.append("\(imageCount) photos (≤ 2048 px), 5 warm-up + 30 measured runs per row. \(machine).")
        return lines.joined(separator: "\n") + "\n"
    }

    public static func csv(_ results: [BenchmarkResult]) -> String {
        var lines = ["engine,compute,size_mb,load_ms,reload_ms,first_run_ms,inference_p50_ms,inference_p90_ms,e2e_p50_ms,iou_vs_vision,peak_mem_mb,failures,error"]
        for r in results {
            let fields: [String] = [
                r.engine, r.compute, r.modelSizeMB.map { String($0) } ?? "",
                String(format: "%.2f", r.loadMS), String(format: "%.2f", r.reloadMS), String(format: "%.2f", r.firstRunMS),
                String(format: "%.2f", r.inferenceP50MS), String(format: "%.2f", r.inferenceP90MS),
                String(format: "%.2f", r.endToEndP50MS), r.meanIoUVsVision.map { String(format: "%.4f", $0) } ?? "",
                String(format: "%.1f", r.peakMemoryMB), String(r.failures), r.error ?? "",
            ]
            lines.append(fields.joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
