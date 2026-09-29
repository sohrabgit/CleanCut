import CoreImage
import Testing
@testable import CleanCutKit

@Suite("Frame analysis (guided capture)", .enabled(if: TestEnvironment.hasMetal))
struct FrameAnalyzerTests {
    let analyzer: FrameAnalyzer
    let thresholds = CaptureThresholds.default

    init() throws {
        analyzer = try FrameAnalyzer()
    }

    @Test func kernelsLoadFromTheFrameworkBundle() {
        #expect(CaptureKernels.shared != nil)
    }

    /// Guards the readback: the kernels store data (not color) in alpha, so a
    /// premultiply or color conversion anywhere would skew every metric.
    @Test func statisticsAreWeightedByTheSubjectMask() {
        let extent = CGRect(x: 0, y: 0, width: 200, height: 100)
        let left = CGRect(x: 0, y: 0, width: 100, height: 100)
        let frame = CIImage(color: CIColor(red: 0.2, green: 0.2, blue: 0.2)).cropped(to: left)
            .composited(over: CIImage(color: CIColor(red: 0.8, green: 0.8, blue: 0.8)))
            .cropped(to: extent)
        // The subject is the right half.
        let mask = CIImage(color: .black).cropped(to: left)
            .composited(over: CIImage(color: .white))
            .cropped(to: extent)

        let metrics = analyzer.analyze(frame, subjectMask: mask)
        #expect(abs(metrics.subjectLuma - 0.8) < 0.01)
        #expect(abs(metrics.frameLuma - 0.5) < 0.01)
        #expect(metrics.highlightClip == 0 && metrics.shadowClip == 0 && metrics.specular == 0)
        #expect(abs(metrics.subjectCoverage - 0.5) < 0.02)
    }

    // MARK: - Sharpness

    @Test func sharpnessDropsSteadilyWithBlur() {
        let scene = SyntheticScene(size: CGSize(width: 480, height: 360), subject: CGRect(x: 160, y: 80, width: 160, height: 200), edgeSoftness: 0.5, texture: 6)
        let scores = [0, 1, 2, 4].map { sigma in
            let frame = sigma == 0 ? scene.source : scene.source.clampedToExtent().applyingGaussianBlur(sigma: Double(sigma)).cropped(to: scene.extent)
            return analyzer.analyze(frame, subjectMask: scene.mask).sharpness
        }
        #expect(zip(scores, scores.dropFirst()).allSatisfy { $0 > $1 }, "\(scores)")
        #expect(scores[0] >= thresholds.minSharpness, "\(scores)")
        #expect(scores[3] < thresholds.minSharpness, "\(scores)")
    }

    /// Sharpness is normalized by the subject's own contrast, so a product
    /// with no texture isn't mistaken for a blurry one.
    @Test func aPlainProductStillReadsAsSharp() {
        let scene = SyntheticScene(size: CGSize(width: 480, height: 360), subject: CGRect(x: 160, y: 80, width: 160, height: 200), edgeSoftness: 0.5)
        let sharp = analyzer.analyze(scene.source, subjectMask: scene.mask).sharpness
        let blurred = analyzer.analyze(scene.source.clampedToExtent().applyingGaussianBlur(sigma: 4).cropped(to: scene.extent), subjectMask: scene.mask).sharpness
        #expect(sharp >= thresholds.minSharpness, "\(sharp)")
        #expect(blurred < thresholds.minSharpness, "\(blurred)")
    }

    /// A shallow depth of field is fine: only the product has to be sharp.
    @Test func aBlurredBackdropDoesNotCountAgainstASharpProduct() {
        let scene = SyntheticScene(size: CGSize(width: 480, height: 360), subject: CGRect(x: 160, y: 80, width: 160, height: 200), edgeSoftness: 0.5, texture: 6)
        let busyBackdrop = SyntheticScene(size: scene.size, subject: scene.extent, texture: 6).source
            .clampedToExtent().applyingGaussianBlur(sigma: 6).cropped(to: scene.extent)
        let frame = scene.source.applyingFilter("CIBlendWithRedMask", parameters: [
            kCIInputBackgroundImageKey: busyBackdrop,
            kCIInputMaskImageKey: scene.mask,
        ]).cropped(to: scene.extent)

        #expect(analyzer.analyze(frame, subjectMask: scene.mask).sharpness >= thresholds.minSharpness)
    }

    @Test func sharpnessDoesNotDependOnTheCameraResolution() {
        let scene = ReplayScene(size: CGSize(width: 1080, height: 1440))
        let large = analyzer.analyze(scene.frame(.good), subjectMask: scene.mask(.good)).sharpness
        let small = ReplayScene(size: CGSize(width: 720, height: 960))
        let native = analyzer.analyze(small.frame(.good), subjectMask: small.mask(.good)).sharpness
        #expect(abs(large - native) / native < 0.5, "\(large) vs \(native)")
    }

    // MARK: - Framing

    @Test func subjectBoundsAreNormalizedWithATopLeftOrigin() throws {
        let scene = SyntheticScene(edgeSoftness: 0)
        let bounds = try #require(analyzer.analyze(scene.source, subjectMask: scene.mask).subjectBounds)
        let expected = CGRect(x: 150.0 / 400, y: 1 - 220.0 / 300, width: 100.0 / 400, height: 130.0 / 300)
        let tolerance = 1.5 / FrameAnalyzer.boundsLongSide
        #expect(abs(bounds.minX - expected.minX) < tolerance && abs(bounds.minY - expected.minY) < tolerance, "\(bounds)")
        #expect(abs(bounds.width - expected.width) < tolerance && abs(bounds.height - expected.height) < tolerance, "\(bounds)")
    }

    @Test(arguments: [
        (CGRect(x: 150, y: 90, width: 100, height: 130), nil),
        (CGRect(x: 0, y: 90, width: 100, height: 130), CaptureIssue.cutOff),
        (CGRect(x: 150, y: 170, width: 100, height: 130), .cutOff),
        (CGRect(x: 180, y: 130, width: 40, height: 50), .tooFar),
    ] as [(CGRect, CaptureIssue?)])
    func framing(subject: CGRect, expected: CaptureIssue?) {
        let scene = SyntheticScene(subject: subject, edgeSoftness: 0.5)
        let metrics = analyzer.analyze(scene.source, subjectMask: scene.mask)
        #expect(CaptureAssessment(metrics).issues[.framing] == expected)
    }

    @Test func noMaskMeansNoSubject() {
        let scene = SyntheticScene()
        let metrics = analyzer.analyze(scene.source, subjectMask: nil)
        #expect(metrics.subjectBounds == nil)
        #expect(CaptureAssessment(metrics).issues[.framing] == .noSubject)
    }

    @Test func anEmptyMaskMeansNoSubject() {
        let scene = SyntheticScene()
        let empty = CIImage(color: .black).cropped(to: scene.extent)
        #expect(CaptureAssessment(analyzer.analyze(scene.source, subjectMask: empty)).issues[.framing] == .noSubject)
    }

    // MARK: - Replay scenarios, end to end

    /// Each staged situation trips exactly the check it was built for, so the
    /// Simulator's replay camera demonstrates every tip.
    @Test(arguments: CaptureScenario.allCases)
    func replayScenarioTriggersOnlyItsIssue(_ scenario: CaptureScenario) {
        let scene = ReplayScene()
        for time in [0.0, 1.7] {
            let metrics = analyzer.analyze(scene.frame(scenario, time: time), subjectMask: scene.mask(scenario, time: time))
            let issues = Set(CaptureAssessment(metrics).issues.values)
            #expect(issues == Set([scenario.expectedIssue].compactMap { $0 }), "\(scenario) at \(time)s: \(metrics)")
        }
    }
}
