import CoreImage
import Foundation
import ImageIO
import Testing
@testable import CleanCutKit

@Suite("BatchProcessor")
struct BatchProcessorTests {
    let renderer = TestEnvironment.renderer
    let scene = SyntheticScene(size: CGSize(width: 320, height: 240), subject: CGRect(x: 110, y: 60, width: 100, height: 120))

    /// Tracks how many segmentations run at once.
    actor ConcurrencyGauge {
        private(set) var current = 0
        private(set) var peak = 0
        func enter() { current += 1; peak = max(peak, current) }
        func leave() { current -= 1 }
    }

    /// Wraps a mask segmenter, holding each call open briefly so overlaps show.
    struct GaugedSegmenter: Segmenter {
        let base: MaskSegmenter
        let gauge: ConcurrencyGauge
        var name: String { "Gauged" }

        func segment(_ image: CGImage) async throws -> SegmentationResult {
            await gauge.enter()
            do {
                try await Task.sleep(for: .milliseconds(30))
                let result = try await base.segment(image)
                await gauge.leave()
                return result
            } catch {
                await gauge.leave()
                throw error
            }
        }
    }

    enum TestError: Error { case unreadable }

    private func makeOutputDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("batch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeJobs(_ count: Int, failing: Set<Int> = []) throws -> [BatchJob] {
        let image = try #require(renderer.makeCGImage(scene.source))
        return (0..<count).map { index in
            BatchJob { _ in
                if failing.contains(index) { throw TestError.unreadable }
                return image
            }
        }
    }

    private func collect(_ stream: AsyncStream<BatchEvent>) async -> (finished: [BatchOutput], failed: Int, started: Int) {
        var finished: [BatchOutput] = []
        var failed = 0, started = 0
        for await event in stream {
            switch event {
            case .started: started += 1
            case .finished(let output): finished.append(output)
            case .failed: failed += 1
            }
        }
        return (finished, failed, started)
    }

    private func processor(_ gauge: ConcurrencyGauge, limit: Int) -> BatchProcessor {
        let base = MaskSegmenter(masks: [scene.mask], renderer: renderer)
        return BatchProcessor(segmenter: GaugedSegmenter(base: base, gauge: gauge), makeRenderer: { [renderer] in renderer }, maxConcurrentJobs: limit)
    }

    @Test(arguments: [1, 2, 3])
    func neverExceedsTheConcurrencyLimit(limit: Int) async throws {
        let gauge = ConcurrencyGauge()
        let result = await collect(processor(gauge, limit: limit).process(
            try makeJobs(8), recipe: .default, presets: [.depop], outputDirectory: try makeOutputDirectory()
        ))
        #expect(result.finished.count == 8)
        let peak = await gauge.peak
        #expect(peak <= limit)
        #expect(peak == limit, "the window should actually fill up")
    }

    @Test func writesOneCorrectlySizedFilePerPreset() async throws {
        let directory = try makeOutputDirectory()
        let presets: [ExportPreset] = [.depop, .vinted, .cutout]
        let result = await collect(processor(ConcurrencyGauge(), limit: 2).process(
            try makeJobs(2), recipe: .default, presets: presets, outputDirectory: directory
        ))
        #expect(result.finished.count == 2)
        for output in result.finished {
            #expect(output.thumbnail != nil)
            for preset in presets {
                let url = try #require(output.files[preset.id])
                let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
                let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
                #expect(properties[kCGImagePropertyPixelWidth] as? Int == preset.pixelWidth)
                #expect(properties[kCGImagePropertyPixelHeight] as? Int == preset.pixelHeight)
            }
        }
    }

    @Test func oneFailureDoesNotStopTheBatch() async throws {
        let result = await collect(processor(ConcurrencyGauge(), limit: 2).process(
            try makeJobs(5, failing: [1, 3]), recipe: .default, presets: [.depop], outputDirectory: try makeOutputDirectory()
        ))
        #expect(result.finished.count == 3)
        #expect(result.failed == 2)
        #expect(result.started == 5)
    }

    @Test func cancellationStopsStartingNewJobs() async throws {
        let stream = processor(ConcurrencyGauge(), limit: 1).process(
            try makeJobs(20), recipe: .default, presets: [.depop], outputDirectory: try makeOutputDirectory()
        )
        let consumer = Task {
            var started = 0
            for await event in stream {
                if case .started = event { started += 1 }
                if case .finished = event { break } // stop listening after the first photo
            }
            return started
        }
        let started = await consumer.value
        #expect(started < 20)
    }
}
