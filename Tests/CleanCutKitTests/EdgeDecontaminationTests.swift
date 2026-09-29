import CoreImage
import Testing
@testable import CleanCutKit

@Suite("Edge decontamination (Metal kernel)", .enabled(if: TestEnvironment.hasMetal))
struct EdgeDecontaminationTests {
    let renderer = TestEnvironment.renderer
    /// Red product on a green lawn, with a wide soft edge so there's a lot of
    /// mixed (contaminated) pixels to measure.
    let scene = SyntheticScene(edgeSoftness: 3)
    let size = CGSize(width: 512, height: 512)

    private func renderCutout(cleanEdges: Bool) -> RGBABitmap {
        let recipe = Recipe(
            shadow: .none,
            edges: EdgeSettings(feather: 0, cleanEdges: cleanEdges, cleanStrength: 1),
            presetID: .cutout
        )
        let image = Pipeline.makeImage(scene.inputs, recipe: recipe, outputSize: size)
        return renderer.rgbaPixels(image, rect: CGRect(origin: .zero, size: size))
    }

    /// Mean distance (0...255 scale) between edge pixels' unpremultiplied color
    /// and the true product color, over pixels with partial coverage.
    private func edgeError(_ bitmap: RGBABitmap) -> (error: Double, samples: Int) {
        let truth = scene.foreground
        var total = 0.0
        var samples = 0
        for y in 0..<bitmap.height {
            for x in 0..<bitmap.width {
                let p = bitmap[x, y]
                guard p.a >= 50, p.a <= 230 else { continue }
                let a = Double(p.a)
                let dr = Double(p.r) / a - truth.red
                let dg = Double(p.g) / a - truth.green
                let db = Double(p.b) / a - truth.blue
                total += (dr * dr + dg * dg + db * db).squareRoot() * 255
                samples += 1
            }
        }
        return (total / Double(max(samples, 1)), samples)
    }

    @Test func kernelLoadsFromTheFrameworkBundle() {
        #expect(EdgeKernels.shared != nil)
    }

    @Test func removesBackdropColorFromSoftEdges() {
        let before = edgeError(renderCutout(cleanEdges: false))
        let after = edgeError(renderCutout(cleanEdges: true))
        #expect(before.samples > 500, "scene should produce a real edge band")
        #expect(after.error < before.error * 0.4, "edge error \(before.error) → \(after.error)")
    }

    @Test func leavesTheInteriorUntouched() {
        let before = renderCutout(cleanEdges: false)
        let after = renderCutout(cleanEdges: true)
        let center = (size.width / 2, size.height / 2)
        #expect(before[Int(center.0), Int(center.1)] == after[Int(center.0), Int(center.1)])
    }

    @Test func zeroStrengthIsANoOp() throws {
        let kernels = try #require(EdgeKernels.shared)
        let source = scene.source
        let matte = Matte.canonical(scene.mask).cropped(to: scene.extent)
        let cleaned = kernels.decontaminate(image: source, matte: matte, strength: 0, backgroundRadius: 8)
        #expect(renderer.rgbaPixels(cleaned, rect: scene.extent) == renderer.rgbaPixels(source, rect: scene.extent))
    }
}
