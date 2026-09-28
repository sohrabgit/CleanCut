import CoreImage
import Testing
@testable import CleanCutKit

@Suite("Pipeline")
struct PipelineTests {
    let renderer = TestEnvironment.renderer
    let scene = SyntheticScene()

    private func render(_ recipe: Recipe, size: CGSize? = nil, scene: SyntheticScene? = nil) -> RGBABitmap {
        let scene = scene ?? self.scene
        let size = size ?? recipe.preset.pixelSize
        let image = Pipeline.makeImage(scene.inputs, recipe: recipe, outputSize: size)
        return renderer.rgbaPixels(image, rect: CGRect(origin: .zero, size: size))
    }

    @Test func bitmapRowsRunTopToBottom() {
        let size = CGSize(width: 4, height: 4)
        let top = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 2, width: 4, height: 2))
        let image = top.composited(over: CIImage(color: .blue)).cropped(to: CGRect(origin: .zero, size: size))
        let bitmap = renderer.rgbaPixels(image)
        #expect(bitmap[0, 0] == .init(r: 255, g: 0, b: 0, a: 255))
        #expect(bitmap[0, 3] == .init(r: 0, g: 0, b: 255, a: 255))
    }

    @Test(arguments: ExportPreset.all)
    func outputMatchesPresetPixelSize(_ preset: ExportPreset) {
        let image = Pipeline.makeImage(scene.inputs, recipe: Recipe(presetID: preset.id), outputSize: preset.pixelSize)
        #expect(image.extent == CGRect(origin: .zero, size: preset.pixelSize))
    }

    @Test func amazonBackgroundIsExactlyPureWhite() {
        let bitmap = render(Recipe(background: .studioSweep(RGBA(hex: 0x334455)), shadow: .natural, presetID: .amazon))
        let white = RGBABitmap.Pixel(r: 255, g: 255, b: 255, a: 255)
        let w = bitmap.width, h = bitmap.height
        for (x, y) in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1), (w / 2, 5), (5, h / 2)] {
            #expect(bitmap[x, y] == white, "pixel (\(x), \(y))")
        }
    }

    @Test func subjectIsCenteredAndFillsThePresetFraction() throws {
        let recipe = Recipe(shadow: .none, presetID: .cutout)
        let bitmap = render(recipe)
        let bounds = try #require(bitmap.opaqueBounds())
        #expect(abs(bounds.midX - CGFloat(bitmap.width) / 2) <= 2)
        #expect(abs(bounds.midY - CGFloat(bitmap.height) / 2) <= 2)
        // The scene's subject is taller than wide, so height hits the 90% fill.
        let fill = bounds.height / CGFloat(bitmap.height)
        #expect(abs(fill - ExportPreset.cutout.fill) < 0.02)
    }

    @Test func cutoutIsTransparentAwayFromTheSubject() {
        let bitmap = render(Recipe(shadow: .none, presetID: .cutout))
        #expect(bitmap[0, 0].a == 0)
        #expect(bitmap[bitmap.width - 1, bitmap.height - 1].a == 0)
        #expect(bitmap[bitmap.width / 2, bitmap.height / 2].a == 255)
    }

    @Test func noShadowLeavesTheBackgroundUntouched() {
        let bitmap = render(Recipe(shadow: .none, presetID: .depop))
        // Below the subject (fill 80% → bottom edge at 90% height), clear of the
        // scene's soft mask edge.
        let belowSubject = bitmap[bitmap.width / 2, Int(Double(bitmap.height) * 0.97)]
        #expect(belowSubject == .init(r: 255, g: 255, b: 255, a: 255))
    }

    @Test func contactShadowDarkensTheFloorButNotTheSky() {
        let bitmap = render(Recipe(shadow: .contact, presetID: .depop))
        let h = Double(bitmap.height)
        let floor = bitmap[bitmap.width / 2, Int(h * 0.905)]
        let sky = bitmap[bitmap.width / 2, Int(h * 0.05)]
        #expect(floor.r < 235, "floor pixel \(floor) should be shaded")
        #expect(sky == .init(r: 255, g: 255, b: 255, a: 255))
    }

    @Test func softShadowFallsAlongTheLightDirection() {
        var recipe = Recipe(shadow: ShadowSettings(kind: .soft, intensity: 1, angle: 0, distance: 0.25, softness: 0.02), presetID: .depop)
        let rightward = render(recipe)
        recipe.shadow.angle = 180
        let leftward = render(recipe)
        // Sample just right of the subject: a 100×130 subject at 80% fill spans
        // roughly 19%–81% of the width.
        let x = Int(Double(rightward.width) * 0.86)
        let y = rightward.height / 2
        #expect(rightward[x, y].r < leftward[x, y].r)
    }

    @Test func previewAndExportLookTheSame() {
        // Preview: proxy-resolution inputs rendered small. Export: 4× inputs
        // rendered large, then downscaled for comparison.
        let recipe = Recipe(shadow: .natural, presetID: .depop)
        let small = CGSize(width: 320, height: 320)
        let preview = render(recipe, size: small)

        let big = scene.scaled(by: 4)
        let export = Pipeline.makeImage(big.inputs, recipe: recipe, outputSize: CGSize(width: 1280, height: 1280))
            .transformed(by: CGAffineTransform(scaleX: 0.25, y: 0.25), highQualityDownsample: true)
        let downscaled = renderer.rgbaPixels(export, rect: CGRect(origin: .zero, size: small))

        let psnr = preview.psnr(against: downscaled)
        #expect(psnr > 32, "PSNR \(psnr) dB")
    }

    /// Regression: a product touching the photo's edge used to smear its edge
    /// pixels across the canvas (resampling clamps at the image border).
    @Test(arguments: [ShadowSettings.Kind.none, .natural])
    func productTouchingThePhotoEdgeDoesNotSmearOutward(_ shadow: ShadowSettings.Kind) {
        let edgeToEdge = SyntheticScene(
            size: CGSize(width: 128, height: 128),
            subject: CGRect(x: 2, y: 2, width: 124, height: 124),
            edgeSoftness: 1
        )
        let bitmap = render(Recipe(shadow: ShadowSettings(kind: shadow), presetID: .depop), scene: edgeToEdge)
        // Row 20 of 1280 lies above both the photo and the subject.
        let smeared = (0..<bitmap.width).filter { bitmap[$0, 20] != .init(r: 255, g: 255, b: 255, a: 255) }
        #expect(smeared.isEmpty, "\(smeared.count) non-white pixels above the photo")
    }

    @Test func renderingIsDeterministic() {
        let recipe = Recipe(background: .studioSweep(RGBA(hex: 0xF1ECE4)), shadow: .natural, presetID: .vinted)
        let size = CGSize(width: 240, height: 300)
        #expect(render(recipe, size: size) == render(recipe, size: size))
    }
}
