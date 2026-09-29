import CoreGraphics
import CoreImage
import Testing
@testable import CleanCutKit

@Suite("LabelMap & hit testing")
struct LabelMapTests {
    /// 10×6 map: instance 1 on the left, instance 2 on the right, background between.
    ///
    ///     1 1 0 0 0 0 0 0 2 2
    ///     1 1 0 0 0 0 0 0 2 2  …
    let map: LabelMap = {
        var labels = [UInt8](repeating: 0, count: 60)
        for y in 0..<6 {
            labels[y * 10 + 0] = 1; labels[y * 10 + 1] = 1
            labels[y * 10 + 8] = 2; labels[y * 10 + 9] = 2
        }
        return LabelMap(width: 10, height: 6, labels: labels)
    }()

    @Test func instancesAreListedInOrder() {
        #expect(map.instances == [1, 2])
    }

    @Test func directHitReturnsTheLabelUnderTheFinger() {
        #expect(InstanceHitTester.instance(at: CGPoint(x: 0.05, y: 0.5), in: map) == 1)
        #expect(InstanceHitTester.instance(at: CGPoint(x: 0.95, y: 0.5), in: map) == 2)
    }

    @Test func nearMissSnapsToTheClosestInstance() {
        // x = 0.25 is one pixel right of instance 1.
        #expect(InstanceHitTester.instance(at: CGPoint(x: 0.25, y: 0.5), in: map, snapRadius: 0.2) == 1)
        #expect(InstanceHitTester.instance(at: CGPoint(x: 0.72, y: 0.5), in: map, snapRadius: 0.2) == 2)
    }

    @Test func farMissHitsNothing() {
        #expect(InstanceHitTester.instance(at: CGPoint(x: 0.5, y: 0.5), in: map, snapRadius: 0.1) == nil)
    }

    @Test func pointsOutsideTheMapHitNothing() {
        #expect(InstanceHitTester.instance(at: CGPoint(x: 1.2, y: 0.5), in: map) == nil)
    }

    @Test func boundingBoxCoversTheSelectedInstances() throws {
        let left = try #require(map.boundingBox(of: [1]))
        #expect(left == CGRect(x: 0, y: 0, width: 0.2, height: 1))
        let both = try #require(map.boundingBox(of: [1, 2]))
        #expect(both == CGRect(x: 0, y: 0, width: 1, height: 1))
        #expect(map.boundingBox(of: [7]) == nil)
    }

    @Test func separatingObjectsNumbersDisconnectedRegionsLargestFirst() {
        // One label for everything, as a salient-object model reports it.
        var labels = [UInt8](repeating: 0, count: 60)
        for y in 0..<6 {
            labels[y * 10 + 0] = 1
            labels[y * 10 + 7] = 1; labels[y * 10 + 8] = 1; labels[y * 10 + 9] = 1
        }
        let separated = LabelMap(width: 10, height: 6, labels: labels).separatingObjects()
        #expect(separated.instances == [1, 2])
        #expect(separated[8, 3] == 1) // the wider region on the right
        #expect(separated[0, 3] == 2)
        #expect(separated[4, 3] == 0) // background stays background
    }

    @Test func specksJoinTheNearestObjectInsteadOfBecomingTheirOwn() {
        var labels = [UInt8](repeating: 0, count: 60)
        for y in 0..<6 { labels[y * 10 + 0] = 1; labels[y * 10 + 1] = 1 }
        labels[3 * 10 + 4] = 1 // a one-pixel speck, 1.7% of the map
        let separated = LabelMap(width: 10, height: 6, labels: labels).separatingObjects(minimumArea: 0.05)
        #expect(separated.instances == [1])
        #expect(separated[4, 3] == 1)
    }

    @Test func nearestInstancesPartitionTheWholeMap() {
        let owners = map.nearestInstances()
        #expect(!owners.labels.contains(0))
        #expect(owners[3, 2] == 1)
        #expect(owners[6, 2] == 2)
    }

    @Test func normalizedTopLeftRectsFlipIntoCoreImageSpace() {
        let rect = CGRect(x: 0.25, y: 0.1, width: 0.5, height: 0.2)
        let flipped = rect.denormalizedFlipped(to: CGSize(width: 200, height: 100))
        #expect(flipped == CGRect(x: 50, y: 70, width: 100, height: 20))
    }
}

@Suite("MaskSegmenter & PreparedPhoto")
struct PreparedPhotoTests {
    let renderer = TestEnvironment.renderer
    let size = CGSize(width: 800, height: 600)
    let leftRect = CGRect(x: 100, y: 200, width: 160, height: 240)
    let rightRect = CGRect(x: 520, y: 100, width: 200, height: 150)

    private func mask(_ rect: CGRect) -> CIImage {
        CIImage(color: .white).cropped(to: rect).composited(over: CIImage(color: .black))
            .cropped(to: CGRect(origin: .zero, size: size))
    }

    private func makePhoto() async throws -> PreparedPhoto {
        let scene = SyntheticScene(size: size, subject: leftRect)
        let image = try #require(renderer.makeCGImage(scene.source))
        let segmenter = MaskSegmenter(masks: [mask(leftRect), mask(rightRect)], renderer: renderer)
        return try await PreparedPhoto.prepare(image, segmenter: segmenter, renderer: renderer)
    }

    @Test func segmenterFindsEveryInstance() async throws {
        let photo = try await makePhoto()
        #expect(photo.instances == [1, 2])
    }

    @Test func subjectBoundsFollowTheSelection() async throws {
        let photo = try await makePhoto()
        let left = try #require(photo.segmentation.subjectBounds(for: [1]))
        // Label maps are ~512 px, so bounds are accurate to about a map pixel.
        let tolerance = size.width / 512 + 1
        #expect(abs(left.minX - leftRect.minX) <= tolerance)
        #expect(abs(left.maxY - leftRect.maxY) <= tolerance)
        let all = try #require(photo.segmentation.subjectBounds(for: nil))
        #expect(abs(all.maxX - rightRect.maxX) <= tolerance)
    }

    @Test func emptySelectionProducesNoInputs() async throws {
        let photo = try await makePhoto()
        #expect(photo.previewInputs(selection: []) == nil)
        #expect(try photo.exportInputs(selection: []) == nil)
    }

    @Test func proxyIsDownscaledAndMasksMatchIt() async throws {
        let photo = try await makePhoto()
        #expect(photo.proxyScale == 1) // 800 px is already below the proxy limit
        #expect(photo.proxyMasks.count == 2)
        #expect(photo.proxyMasks[1]?.extent == photo.proxySource.extent)
    }

    /// Regression: combining opaque masks additively produced alpha 2, which
    /// halved the coverage once unpremultiplied (a washed-out, see-through cutout).
    @Test func combinedMaskKeepsFullCoverage() async throws {
        let photo = try await makePhoto()
        let matte = Matte.canonical(photo.proxyMask(for: nil)).cropped(to: photo.proxySource.extent)
        let bitmap = renderer.rgbaPixels(matte)
        #expect(bitmap[Int(leftRect.midX), Int(size.height - leftRect.midY)].r == 255)
        #expect(bitmap[Int(rightRect.midX), Int(size.height - rightRect.midY)].r == 255)
    }

    @Test func previewAndExportInputsAgree() async throws {
        let photo = try await makePhoto()
        let recipe = Recipe(shadow: .none, presetID: .depop)
        let size = CGSize(width: 256, height: 256)
        let rect = CGRect(origin: .zero, size: size)
        let preview = try #require(photo.previewInputs(selection: nil))
        let export = try #require(try photo.exportInputs(selection: nil))
        let a = renderer.rgbaPixels(Pipeline.makeImage(preview, recipe: recipe, outputSize: size), rect: rect)
        let b = renderer.rgbaPixels(Pipeline.makeImage(export, recipe: recipe, outputSize: size), rect: rect)
        #expect(a.psnr(against: b) > 35)
    }

    @Test func splitMaskRecombinesIntoTheOriginal() throws {
        let rect = CGRect(origin: .zero, size: size)
        let both = mask(leftRect).applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: mask(rightRect)])
            .applyingGaussianBlur(sigma: 3).cropped(to: rect)
        let labelMap = try LabelMap(masks: [both], imageSize: size, renderer: renderer).separatingObjects()
        let result = SegmentationResult(imageSize: size, labelMap: labelMap, splitting: both)
        #expect(result.instances == [1, 2])

        let original = renderer.rgbaPixels(both, rect: rect)
        let recombined = renderer.rgbaPixels(
            try result.mask(for: [1]).applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: try result.mask(for: [2])]),
            rect: rect
        )
        #expect(recombined.psnr(against: original) > 50)
    }

    @Test func proxyMaskOnlyCoversSelectedInstances() async throws {
        let photo = try await makePhoto()
        let bitmap = renderer.rgbaPixels(photo.proxyMask(for: [2]), rect: photo.proxySource.extent)
        // Bitmaps are top-left origin; convert rect centers.
        let leftCenter = (Int(leftRect.midX), Int(size.height - leftRect.midY))
        let rightCenter = (Int(rightRect.midX), Int(size.height - rightRect.midY))
        #expect(bitmap[leftCenter.0, leftCenter.1].r == 0)
        #expect(bitmap[rightCenter.0, rightCenter.1].r == 255)
    }
}
