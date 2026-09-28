import CoreGraphics
import CoreML
import Foundation
import Testing
@testable import CleanCutKit

@Suite("CoreMLSegmenter (U²-Netp)")
struct CoreMLSegmenterTests {
    let renderer = TestEnvironment.renderer

    /// The committed model package, located relative to this source file.
    static let packageURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Models/U2Netp.mlpackage")

    private func makeSegmenter(_ units: MLComputeUnits = .cpuOnly) async throws -> CoreMLSegmenter {
        let compiled = try await CoreMLSegmenter.compile(Self.packageURL)
        return try CoreMLSegmenter(compiledModelAt: compiled, name: "U²-Netp", computeUnits: units, renderer: renderer)
    }

    @Test func findsTheSalientObjectInASyntheticProductShot() async throws {
        let scene = SyntheticScene(size: CGSize(width: 480, height: 360), subject: CGRect(x: 170, y: 90, width: 140, height: 180))
        let image = try #require(renderer.makeCGImage(scene.source))
        let (result, timings) = try await makeSegmenter().segmentWithTimings(image)

        #expect(result.instances == [1])
        #expect(try result.mask(for: nil).extent.size == scene.size)
        #expect(timings.inference > .zero)

        // The model's mask should agree with the scene's ground truth.
        let truth = try LabelMap(masks: [scene.mask], imageSize: scene.size, renderer: renderer)
        let iou = SegmentationBenchmark.foregroundIoU(result.labelMap, truth)
        #expect(iou > 0.8, "IoU \(iou)")
    }
}

@Suite("FallbackSegmenter")
struct FallbackSegmenterTests {
    struct Failing: Segmenter {
        let error: SegmentationError
        var name: String { "Failing" }
        func segment(_ image: CGImage) async throws -> SegmentationResult { throw error }
    }

    let renderer = TestEnvironment.renderer
    let scene = SyntheticScene()

    private var backup: MaskSegmenter { MaskSegmenter(name: "Backup", masks: [scene.mask], renderer: renderer) }

    @Test func fallsBackWhenThePrimaryCannotRunHere() async throws {
        let image = try #require(renderer.makeCGImage(scene.source))
        let segmenter = FallbackSegmenter(primary: Failing(error: .unavailable("simulator")), fallback: backup)
        let result = try await segmenter.segment(image)
        #expect(result.instances == [1])
        #expect(segmenter.lastUsedName == "Backup")
    }

    @Test func reportsRealFailuresInsteadOfFallingBack() async throws {
        let image = try #require(renderer.makeCGImage(scene.source))
        let segmenter = FallbackSegmenter(primary: Failing(error: .noSubject), fallback: backup)
        await #expect(throws: SegmentationError.noSubject) {
            try await segmenter.segment(image)
        }
    }
}
