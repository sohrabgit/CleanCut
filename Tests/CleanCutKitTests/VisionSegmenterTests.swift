import CoreGraphics
import Foundation
import Testing
@testable import CleanCutKit

/// Integration tests against the real Vision model. They need a real photo:
/// the committed sample fixtures, or `CLEANCUT_TEST_PHOTO=/path/to/photo`.
// Vision's instance mask can't create an inference context in the Simulator.
@Suite("VisionSegmenter (integration)", .enabled(if: VisionFixtures.photoURL != nil && !TestEnvironment.isSimulator))
struct VisionSegmenterTests {
    let renderer = TestEnvironment.renderer

    private func loadPhoto() throws -> CGImage {
        let url = try #require(VisionFixtures.photoURL)
        return try ImageLoader.load(url: url, maxPixelSize: 1024)
    }

    @Test func findsAForegroundObject() async throws {
        let image = try loadPhoto()
        let result = try await VisionSegmenter().segment(image)
        #expect(!result.instances.isEmpty)
        #expect(result.labelMap.instances == result.instances)
        #expect(result.imageSize == CGSize(width: image.width, height: image.height))
        let bounds = try #require(result.subjectBounds(for: nil))
        #expect(bounds.width > 10 && bounds.height > 10)
    }

    @Test func fullResolutionMaskMatchesTheImage() async throws {
        let image = try loadPhoto()
        let result = try await VisionSegmenter().segment(image)
        let mask = try result.mask(for: nil)
        #expect(mask.extent.size == CGSize(width: image.width, height: image.height))
    }

    @Test func preparesAPhotoForEditing() async throws {
        let image = try loadPhoto()
        let photo = try await PreparedPhoto.prepare(image, segmenter: VisionSegmenter(), renderer: renderer)
        #expect(photo.proxyMasks.count == photo.instances.count)
        let inputs = try #require(photo.previewInputs(selection: nil))
        let output = Pipeline.makeImage(inputs, recipe: .default, outputSize: CGSize(width: 256, height: 256))
        let bitmap = renderer.rgbaPixels(output, rect: CGRect(x: 0, y: 0, width: 256, height: 256))
        #expect(bitmap[0, 0] == .init(r: 255, g: 255, b: 255, a: 255))
    }
}

enum VisionFixtures {
    static let photoURL: URL? = {
        if let path = ProcessInfo.processInfo.environment["CLEANCUT_TEST_PHOTO"] {
            return URL(fileURLWithPath: path)
        }
        let bundle = Bundle(for: FixtureToken.self)
        return bundle.url(forResource: "product-photo", withExtension: "jpg", subdirectory: "Fixtures")
            ?? bundle.url(forResource: "product-photo", withExtension: "jpg")
    }()
}

private final class FixtureToken {}
