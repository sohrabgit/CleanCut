import CoreGraphics
import CoreImage
import Testing
@testable import CleanCutKit

/// The harnesses behind `cleancut-bench` and the app's Benchmarks screen. The
/// numbers depend on the machine; these tests check that each harness measures
/// what it says, on the schedule it says.
@Suite("Benchmarks")
struct BenchmarkTests {
    @Test func percentileIsNearestRank() {
        let values = (1...10).map(Double.init).shuffled()
        #expect(SegmentationBenchmark.percentile(values, 0.5) == 5)
        #expect(SegmentationBenchmark.percentile(values, 0.9) == 9)
        #expect(SegmentationBenchmark.percentile([], 0.5) == 0)
    }

    @Test func machineDescriptionNamesTheHardwareAndOS() {
        #expect(!BenchmarkMachine.hardware.isEmpty)
        #if os(macOS)
        #expect(BenchmarkMachine.description.contains("macOS"))
        #else
        #expect(BenchmarkMachine.description.contains("iOS"))
        #endif
    }

    @Test func visionIsTheOnlyReferenceConfiguration() {
        let configurations = BenchmarkConfiguration.vision
            + BenchmarkConfiguration.coreML(compiledModelAt: URL(fileURLWithPath: "/unused.mlmodelc"), name: "Model", sizeMB: 1, renderer: TestEnvironment.renderer)
        #expect(configurations.filter(\.isReference).map(\.compute) == ["Auto"])
        #expect(configurations.filter { $0.engine == "Model" }.map(\.compute) == ["CPU", "CPU+GPU", "CPU+ANE", "All"])
    }

    @Test(.enabled(if: TestEnvironment.hasEdgeKernels))
    func previewBenchmarkTimesEveryScenario() async throws {
        let scene = SyntheticScene(size: CGSize(width: 480, height: 360), subject: CGRect(x: 170, y: 90, width: 140, height: 180))
        let benchmark = PreviewBenchmark(inputs: scene.inputs, size: CGSize(width: 240, height: 240), frames: 4, warmupFrames: 1)
        var rows: [PreviewBenchmark.Row] = []
        for scenario in PreviewBenchmark.scenarios {
            rows.append(try await benchmark.run(scenario, renderer: TestEnvironment.renderer))
        }

        #expect(rows.map(\.scenario) == PreviewBenchmark.scenarios.map(\.name))
        for row in rows {
            #expect(row.gpuP50MS > 0 && row.gpuP50MS <= row.gpuP90MS, "\(row)")
            // A frame's wall time includes its GPU time.
            #expect(row.frameP50MS >= row.gpuP50MS, "\(row)")
        }
        let markdown = PreviewBenchmark.markdown(rows)
        #expect(markdown.split(separator: "\n").count == 2 + rows.count)
    }

    @Test(.enabled(if: TestEnvironment.hasMetal))
    func captureBenchmarkWithoutAModelTimesOnlyTheStatistics() async throws {
        let benchmark = CaptureBenchmark(frameSize: CGSize(width: 360, height: 480), frames: 6, warmupFrames: 1, maskInterval: 3)
        let result = try await benchmark.run(analyzer: try FrameAnalyzer(), segmenter: nil)

        #expect(result.analysisP50MS > 0)
        #expect(result.maskP50MS == nil)
        #expect(result.frameP90MS >= result.analysisP50MS)
        #expect(CaptureBenchmark.markdown(result).contains("| Subject mask (U²-Netp `liveMask`, 1 frame in 3) | – | – |"))
    }

    /// The mask runs on one frame in `maskInterval`, as in the app, so with a
    /// model the slow frames show up at p90 but not at p50.
    @Test(.enabled(if: TestEnvironment.hasMetal))
    func captureBenchmarkRefreshesTheMaskOnTheAppsSchedule() async throws {
        let compiled = try await CoreMLSegmenter.compile(CoreMLSegmenterTests.packageURL)
        let segmenter = try CoreMLSegmenter(compiledModelAt: compiled, name: "U²-Netp", computeUnits: .cpuOnly, renderer: TestEnvironment.renderer)
        let benchmark = CaptureBenchmark(frameSize: CGSize(width: 360, height: 480), frames: 9, warmupFrames: 0, maskInterval: 3)
        let result = try await benchmark.run(analyzer: try FrameAnalyzer(), segmenter: segmenter)

        let mask = try #require(result.maskP50MS)
        #expect(mask > 0)
        #expect(result.frameP90MS >= mask)
        #expect(result.frameP50MS < mask)
        #expect(result.frameMeanMS > result.analysisP50MS)
    }

    @Test func deviceReportHasASectionPerBenchmarkAndAStableFileName() throws {
        let segmentation = BenchmarkResult(
            engine: "U²-Netp", compute: "CPU+ANE", modelSizeMB: 2.4, loadMS: 20, reloadMS: 19, loadsLazily: false, firstRunMS: 9,
            inferenceP50MS: 4.6, inferenceP90MS: 4.8, endToEndP50MS: 7.8, meanIoUVsVision: 0.958, peakMemoryMB: 25, failures: 0
        )
        let preview = PreviewBenchmark.Row(scenario: "Redraw, nothing changed", gpuP50MS: 0.1, gpuP90MS: 0.1, frameP50MS: 0.5, frameP90MS: 0.9)
        let capture = CaptureBenchmark.Result(
            frameSize: CGSize(width: 1080, height: 1440), maskInterval: 3, analysisP50MS: 3, analysisP90MS: 4,
            maskP50MS: 12, maskP90MS: 13, frameP50MS: 3.1, frameP90MS: 16, frameMeanMS: 7
        )
        let components = DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: .current, year: 2026, month: 9, day: 29, hour: 8, minute: 5)
        let report = DeviceBenchmarkReport(
            hardware: "iPhone12,8", machine: "iPhone12,8, iOS 26.0", date: try #require(components.date),
            thermalStateAtStart: "nominal", thermalStateAtEnd: "fair",
            segmentation: [segmentation], photoCount: 3, preview: [preview], previewSize: CGSize(width: 750, height: 750), capture: capture
        )

        let markdown = report.markdown
        for heading in ["# CleanCut benchmarks: iPhone12,8, iOS 26.0", "## Segmentation", "## Live preview frame time", "## Guided capture analysis"] {
            #expect(markdown.contains(heading), "missing \(heading)")
        }
        #expect(markdown.contains("| U²-Netp | CPU+ANE | 2.4 MB | 20.0 ms |"))
        #expect(markdown.contains("at 750×750"))
        #expect(markdown.contains("Budget at 15 fps: 66.7 ms"))
        #expect(markdown.contains("nominal at the start, fair at the end"))
        #expect(report.fileStem == "iPhone12-8-20260929-0805")
        #expect(report.csv.split(separator: "\n").count == 2)
    }
}
