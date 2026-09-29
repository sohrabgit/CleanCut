import CoreGraphics
import Testing
@testable import CleanCutKit

@Suite("Framing")
struct FramingTests {
    private func fillFractions(_ subject: CGRect, in canvas: CGRect) -> (width: Double, height: Double) {
        (subject.width / canvas.width, subject.height / canvas.height)
    }

    @Test(arguments: ExportPreset.all)
    func canvasMatchesPresetAspectRatio(_ preset: ExportPreset) {
        let subject = CGRect(x: 120, y: 340, width: 900, height: 1400)
        let canvas = Framing.canvasRect(subject: subject, aspectRatio: preset.aspectRatio, fill: preset.fill)
        #expect(abs(canvas.width / canvas.height - preset.aspectRatio) < 1e-9)
    }

    @Test func tallSubjectIsLimitedByHeight() {
        let subject = CGRect(x: 0, y: 0, width: 200, height: 1000)
        let canvas = Framing.canvasRect(subject: subject, aspectRatio: 1, fill: 0.8)
        let fill = fillFractions(subject, in: canvas)
        #expect(abs(fill.height - 0.8) < 1e-9)
        #expect(fill.width < 0.8)
    }

    @Test func wideSubjectIsLimitedByWidth() {
        let subject = CGRect(x: 0, y: 0, width: 1600, height: 300)
        let canvas = Framing.canvasRect(subject: subject, aspectRatio: 4.0 / 5.0, fill: 0.8)
        let fill = fillFractions(subject, in: canvas)
        #expect(abs(fill.width - 0.8) < 1e-9)
        #expect(fill.height < 0.8)
    }

    @Test func subjectIsCentered() {
        let subject = CGRect(x: 37, y: 911, width: 420, height: 380)
        let canvas = Framing.canvasRect(subject: subject, aspectRatio: 1, fill: 0.85)
        #expect(abs(canvas.midX - subject.midX) < 1e-9)
        #expect(abs(canvas.midY - subject.midY) < 1e-9)
    }

    @Test func emptySubjectStillProducesAValidCanvas() {
        let canvas = Framing.canvasRect(subject: .zero, aspectRatio: 1, fill: 0.8)
        #expect(canvas.width > 0)
        #expect(canvas.height > 0)
    }

    @Test func transformMapsCanvasOntoOutputPixels() {
        let canvas = CGRect(x: 100, y: 200, width: 1000, height: 1250)
        let output = CGSize(width: 1200, height: 1500)
        let mapped = canvas.applying(Framing.transform(from: canvas, to: output))
        #expect(abs(mapped.minX) < 1e-9)
        #expect(abs(mapped.minY) < 1e-9)
        #expect(abs(mapped.width - 1200) < 1e-9)
        #expect(abs(mapped.height - 1500) < 1e-9)
    }
}

@Suite("ViewportMath")
struct ViewportMathTests {
    @Test func aspectFitLetterboxesWideContent() {
        let rect = ViewportMath.aspectFit(CGSize(width: 200, height: 100), in: CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(rect == CGRect(x: 0, y: 25, width: 100, height: 50))
    }

    @Test func aspectFitPillarboxesTallContent() {
        let rect = ViewportMath.aspectFit(CGSize(width: 100, height: 400), in: CGRect(x: 10, y: 0, width: 300, height: 200))
        #expect(rect == CGRect(x: 135, y: 0, width: 50, height: 200))
    }

    @Test func normalizedPointMapsCornersAndRejectsOutside() {
        let imageRect = CGRect(x: 0, y: 25, width: 100, height: 50)
        #expect(ViewportMath.normalizedPoint(CGPoint(x: 0, y: 25), inImageRect: imageRect) == .zero)
        #expect(ViewportMath.normalizedPoint(CGPoint(x: 50, y: 50), inImageRect: imageRect) == CGPoint(x: 0.5, y: 0.5))
        #expect(ViewportMath.normalizedPoint(CGPoint(x: 50, y: 10), inImageRect: imageRect) == nil)
    }
}
