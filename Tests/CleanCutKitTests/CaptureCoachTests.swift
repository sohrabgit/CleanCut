import CoreGraphics
import Testing
@testable import CleanCutKit

@Suite("Capture coach")
struct CaptureCoachTests {
    let start = ContinuousClock.now

    private func at(_ milliseconds: Int) -> ContinuousClock.Instant {
        start.advanced(by: .milliseconds(milliseconds))
    }

    private func assessment(_ issues: CaptureIssue...) -> CaptureAssessment {
        CaptureAssessment(issues: Dictionary(uniqueKeysWithValues: issues.map { ($0.check, $0) }))
    }

    @Test func nothingIsReadyBeforeTheFirstFrame() {
        let guidance = CaptureCoach().guidance
        #expect(guidance == .pending)
        #expect(!guidance.isReady)
        #expect(guidance.passes(.sharpness) == nil)
    }

    @Test func theFirstFrameIsAdoptedImmediately() {
        var coach = CaptureCoach()
        let guidance = coach.update(assessment(.blurry), at: at(0))
        #expect(guidance.tip == .blurry)
        #expect(guidance.passes(.sharpness) == false)
        #expect(guidance.passes(.light) == true)
    }

    @Test func aOneFrameBlipDoesNotChangeTheTip() {
        var coach = CaptureCoach()
        _ = coach.update(assessment(.blurry), at: at(0))
        _ = coach.update(assessment(), at: at(100))
        let guidance = coach.update(assessment(.blurry), at: at(200))
        #expect(guidance.tip == .blurry)
        // The blip's clock was reset, so a later short pass doesn't count either.
        #expect(coach.update(assessment(), at: at(500)).tip == .blurry)
    }

    @Test func aSustainedChangeWinsAfterTheHoldTime() {
        var coach = CaptureCoach(holdTime: .milliseconds(400))
        _ = coach.update(assessment(.blurry), at: at(0))
        #expect(coach.update(assessment(), at: at(100)).tip == .blurry)
        #expect(coach.update(assessment(), at: at(400)).tip == .blurry)
        let guidance = coach.update(assessment(), at: at(500))
        #expect(guidance.tip == nil)
        #expect(guidance.isReady)
    }

    @Test func switchingBetweenTwoIssuesAlsoWaits() {
        var coach = CaptureCoach()
        _ = coach.update(assessment(.tooDark), at: at(0))
        #expect(coach.update(assessment(.tooBright), at: at(100)).tip == .tooDark)
        #expect(coach.update(assessment(.tooBright), at: at(600)).tip == .tooBright)
    }

    @Test func tipsFollowCheckPriority() {
        var coach = CaptureCoach()
        let guidance = coach.update(assessment(.glare, .blurry, .tooDark, .cutOff), at: at(0))
        #expect(guidance.tip == .cutOff)
        #expect(guidance.issues.count == 4)
        #expect(!guidance.isReady)
    }

    // MARK: - Assessment

    private let good = FrameMetrics(
        sharpness: 2, subjectLuma: 0.5, frameLuma: 0.5,
        subjectBounds: CGRect(x: 0.3, y: 0.2, width: 0.4, height: 0.6), subjectCoverage: 0.2
    )

    @Test func aGoodFrameHasNoIssues() {
        #expect(CaptureAssessment(good).issues.isEmpty)
    }

    @Test func overexposureIsReportedAsLightNotGlare() {
        var metrics = good
        metrics.highlightClip = 0.6
        metrics.specular = 0.3
        #expect(CaptureAssessment(metrics).issues == [.light: .tooBright])
    }

    @Test func smallHotspotsAreGlare() {
        var metrics = good
        metrics.specular = 0.01
        metrics.highlightClip = 0.01
        #expect(CaptureAssessment(metrics).issues == [.glare: .glare])
    }

    @Test func darknessComesFromTheSceneOrCrushedShadows() {
        var dim = good
        dim.frameLuma = 0.1
        var crushed = good
        crushed.shadowClip = 0.5
        #expect(CaptureAssessment(dim).issues == [.light: .tooDark])
        #expect(CaptureAssessment(crushed).issues == [.light: .tooDark])
    }

    @Test func aSpeckOfMaskIsNotASubject() {
        var metrics = good
        metrics.subjectCoverage = 0.001
        #expect(CaptureAssessment(metrics).issues[.framing] == .noSubject)
    }

    @Test func aTallNarrowProductIsCloseEnough() {
        var metrics = good
        metrics.subjectBounds = CGRect(x: 0.45, y: 0.2, width: 0.1, height: 0.6)
        #expect(CaptureAssessment(metrics).issues[.framing] == nil)
    }

    // MARK: - Replay timeline

    @Test func theReplayTimelineLoopsThroughEveryTip() {
        let total = ReplayScene.timeline.reduce(0) { $0 + $1.seconds }
        #expect(ReplayScene.scenario(at: 0) == ReplayScene.timeline[0].scenario)
        #expect(ReplayScene.scenario(at: total - 0.01) == .good)
        #expect(ReplayScene.scenario(at: total + 0.01) == ReplayScene.timeline[0].scenario)
        let shown = Set(ReplayScene.timeline.compactMap(\.scenario.expectedIssue))
        #expect(shown.isSuperset(of: [.tooFar, .cutOff, .tooDark, .blurry, .glare]))
    }
}
