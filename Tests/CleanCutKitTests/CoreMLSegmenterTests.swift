import CoreGraphics
import CoreImage
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

    /// Regression: the model's single mask covered both products as one
    /// "Object 1", so in the Simulator (where U²-Netp stands in for Vision) the
    /// Select tool found one object and tapping it did nothing.
    @Test func separateProductsBecomeSeparateSelectableObjects() async throws {
        let size = CGSize(width: 480, height: 360)
        let left = SyntheticScene(size: size, subject: CGRect(x: 60, y: 80, width: 150, height: 200))
        let right = SyntheticScene(size: size, subject: CGRect(x: 330, y: 110, width: 60, height: 140), foreground: RGBA(hex: 0xE8E02A))
        let source = right.source.applyingFilter("CIBlendWithRedMask", parameters: [
            kCIInputBackgroundImageKey: left.source,
            kCIInputMaskImageKey: right.mask,
        ])
        let image = try #require(renderer.makeCGImage(source, rect: left.extent))
        let result = try await makeSegmenter().segment(image)

        #expect(result.instances == [1, 2])
        let map = result.labelMap
        let center = { (rect: CGRect) in CGPoint(x: rect.midX / size.width, y: 1 - rect.midY / size.height) }
        #expect(InstanceHitTester.instance(at: center(left.subject), in: map) == 1) // largest first
        #expect(InstanceHitTester.instance(at: center(right.subject), in: map) == 2)

        // Each object's mask covers only that object.
        let bitmap = renderer.rgbaPixels(try result.mask(for: [2]), rect: CGRect(origin: .zero, size: size))
        #expect(bitmap[Int(left.subject.midX), Int(size.height - left.subject.midY)].r < 10)
        #expect(bitmap[Int(right.subject.midX), Int(size.height - right.subject.midY)].r > 200)
    }

    /// Guided capture's live mask finds the replay camera's bottle, so the
    /// Simulator exercises the same path as a device.
    @Test func liveMaskFindsTheReplayProduct() async throws {
        let scene = ReplayScene(size: CGSize(width: 540, height: 720))
        let frame = scene.frame(.good).transformed(by: CGAffineTransform(translationX: 10, y: 20))
        let mask = try await makeSegmenter().liveMask(for: frame)
        #expect(mask.extent == frame.extent)

        let truth = try LabelMap(masks: [scene.mask(.good)], imageSize: scene.size, renderer: renderer)
        let live = try LabelMap(masks: [mask.transformed(by: CGAffineTransform(translationX: -10, y: -20))], imageSize: scene.size, renderer: renderer)
        let iou = SegmentationBenchmark.foregroundIoU(live, truth)
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
