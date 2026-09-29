import CleanCutKit
import CoreGraphics
import CoreML
import SwiftUI
import UIKit

/// Runs the Kit's benchmark harnesses on this device, the same ones behind
/// `cleancut-bench`, so docs/BENCHMARKS.md can have a table per chip.
@Observable
final class LabModel {
    enum Phase {
        case idle
        case running(step: String, progress: Double)
        case finished(DeviceBenchmarkReport, files: [URL])
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// Photos added from the library, on top of the bundled samples.
    private(set) var pickedPhotos: [Data] = []

    /// Benchmark photos: the bundled samples plus picked ones.
    var photoCount: Int { SampleLibrary.all.count + pickedPhotos.count }

    var isRunning: Bool {
        if case .running = phase { true } else { false }
    }

    /// `-runLab` starts a run as soon as the screen appears, so a script can
    /// collect a report with `devicectl` without anyone tapping.
    static let runsOnLaunch = ProcessInfo.processInfo.arguments.contains("-runLab")

    func setPickedPhotos(_ photos: [Data]) {
        pickedPhotos = photos
    }

    /// - Parameter previewSide: The canvas size in pixels (square), so frame
    ///   times are for this screen's drawable.
    func run(previewSide: Int) async {
        guard !isRunning else { return }
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }

        let thermalStateAtStart = BenchmarkMachine.thermalState
        do {
            phase = .running(step: "Preparing photos", progress: 0)
            let photos = try await Self.loadPhotos(samples: SampleLibrary.all.map(\.imageURL), picked: pickedPhotos)

            let renderer = RenderService()
            var configurations = BenchmarkConfiguration.vision
            if let model = Bundle.main.url(forResource: "U2Netp", withExtension: "mlmodelc") {
                configurations += BenchmarkConfiguration.coreML(compiledModelAt: model, name: "U²-Netp", sizeMB: 2.4, renderer: renderer)
            }
            // Segmentation dominates the run time; preview and capture take the last fifth.
            let steps = Double(configurations.count) / 0.8
            var segmentation: [BenchmarkResult] = []
            for (index, configuration) in configurations.enumerated() {
                phase = .running(step: "Segmentation: \(configuration.engine) on \(configuration.compute)", progress: Double(index) / steps)
                segmentation.append(await Self.segment(configuration, photos: photos))
            }

            phase = .running(step: "Live preview", progress: 0.8)
            let size = CGSize(width: previewSide, height: previewSide)
            let preview = try await Self.preview(photos.images[0], size: size, renderer: renderer)

            phase = .running(step: "Guided capture analysis", progress: 0.92)
            let capture = try await Self.capture()

            let report = DeviceBenchmarkReport(
                thermalStateAtStart: thermalStateAtStart,
                thermalStateAtEnd: BenchmarkMachine.thermalState,
                segmentation: segmentation,
                photoCount: photos.images.count,
                preview: preview,
                previewSize: size,
                capture: capture
            )
            phase = .finished(report, files: try Self.save(report))
        } catch {
            phase = .failed(FriendlyError.message(for: error))
        }
    }

    // MARK: - Work off the main actor

    nonisolated private struct Photos: Sendable {
        let images: [CGImage]
        /// Vision's label maps, for the agreement column; `nil` where Vision
        /// can't run (the Simulator).
        let reference: [LabelMap]?
    }

    /// Decodes like the editor does for segmentation work (≤ 2048 px) and keeps
    /// the photos Vision finds a product in, as `cleancut-bench segment` does.
    @concurrent
    private static func loadPhotos(samples: [URL], picked: [Data]) async throws -> Photos {
        var images = try samples.map { try ImageLoader.load(url: $0, maxPixelSize: 2048) }
        images += picked.compactMap { try? ImageLoader.load(data: $0, maxPixelSize: 2048) }
        guard !images.isEmpty else { throw BenchmarkError.noPhotos }

        var detected: [CGImage] = [], reference: [LabelMap] = []
        for image in images {
            guard let result = try? await VisionSegmenter().segment(image) else { continue }
            detected.append(image)
            reference.append(result.labelMap)
        }
        return detected.isEmpty ? Photos(images: images, reference: nil) : Photos(images: detected, reference: reference)
    }

    @concurrent
    private static func segment(_ configuration: BenchmarkConfiguration, photos: Photos) async -> BenchmarkResult {
        await SegmentationBenchmark(images: photos.images).run(configuration, reference: configuration.isReference ? nil : photos.reference)
    }

    @concurrent
    private static func preview(_ image: CGImage, size: CGSize, renderer: RenderService) async throws -> [PreviewBenchmark.Row] {
        let segmenter = FallbackSegmenter(primary: VisionSegmenter(), fallback: try Segmenters.u2netp(renderer: renderer))
        let photo = try await PreparedPhoto.prepare(image, segmenter: segmenter, renderer: renderer)
        guard let inputs = photo.previewInputs(selection: nil) else { throw SegmentationError.noSubject }
        let benchmark = PreviewBenchmark(inputs: inputs, size: size)
        var rows: [PreviewBenchmark.Row] = []
        for scenario in PreviewBenchmark.scenarios {
            rows.append(try await benchmark.run(scenario, renderer: renderer))
        }
        return rows
    }

    /// Guided capture's analysis, set up exactly as `CaptureModel` sets it up.
    @concurrent
    private static func capture() async throws -> CaptureBenchmark.Result {
        let analyzer = try FrameAnalyzer()
        let segmenter = try? Segmenters.u2netp(renderer: RenderService(cacheIntermediates: false))
        return try await CaptureBenchmark(maskInterval: LiveAnalysis.maskInterval).run(analyzer: analyzer, segmenter: segmenter)
    }

    /// Writes `Documents/Benchmarks/<device>-<time>.md` and `.csv`. Copy them
    /// off a device with `xcrun devicectl device copy from --domain-type appDataContainer`.
    private static func save(_ report: DeviceBenchmarkReport) throws -> [URL] {
        let folder = URL.documentsDirectory.appending(path: "Benchmarks", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let markdown = folder.appending(path: "\(report.fileStem).md")
        let csv = folder.appending(path: "\(report.fileStem).csv")
        try report.markdown.write(to: markdown, atomically: true, encoding: .utf8)
        try report.csv.write(to: csv, atomically: true, encoding: .utf8)
        return [markdown, csv]
    }
}
