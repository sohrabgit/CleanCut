import CleanCutKit
import CoreImage
import os
import SwiftUI

/// Guided capture's state: the feed, the live analysis and the coach.
@Observable
final class CaptureModel {
    enum Phase: Equatable {
        case starting
        case live
        case accessDenied
        case failed(String)
    }

    private(set) var phase: Phase = .starting
    private(set) var guidance: CaptureGuidance = .pending
    /// Normalized, top-left origin; `nil` while no product is in view.
    private(set) var subjectBounds: CGRect?
    /// The replay camera's current frame (the real camera draws its own preview).
    private(set) var replayFrame: CGImage?
    private(set) var isCapturing = false
    private(set) var captureError: String?
    /// Last frame's analysis time, for the frame-timing HUD.
    private(set) var analysisTime: Duration?
    var isInterrupted = false

    let isSimulated: Bool
    /// Present for the real camera only.
    let preview: PreviewSession?
    private let feed: any CameraFeed
    private let camera: CameraEngine?
    private var coach = CaptureCoach()

    private static let signposter = OSSignposter(subsystem: "dev.sohrab.cleancut", category: "Capture")

    /// Filming `ReplayScene`: one held scenario, or the looping timeline.
    struct Replay {
        let scenario: CaptureScenario?
    }

    /// The Simulator, and UI tests that pass `-captureReplay [scenario]`, get
    /// the replay camera; `nil` means the real one.
    static var replay: Replay? {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-captureReplay") {
            let next = arguments.index(after: index)
            return Replay(scenario: next < arguments.endIndex ? CaptureScenario(rawValue: arguments[next]) : nil)
        }
        #if targetEnvironment(simulator)
        return Replay(scenario: nil)
        #else
        return nil
        #endif
    }

    static var isAvailable: Bool {
        replay != nil || CameraEngine.isAvailable
    }

    init() {
        if let replay = Self.replay {
            feed = ReplayFeed(scenario: replay.scenario)
            camera = nil
            preview = nil
            isSimulated = true
        } else {
            let camera = CameraEngine()
            feed = camera
            self.camera = camera
            preview = camera.preview
            isSimulated = false
        }
    }

    /// Starts the feed and coaches until the view goes away (task cancellation).
    func run() async {
        let analysis = await Self.makeAnalysis()
        do {
            try await feed.start()
        } catch CameraFeedError.accessDenied {
            phase = .accessDenied
            return
        } catch {
            phase = .failed(FriendlyError.message(for: error))
            return
        }
        phase = .live

        for await frame in feed.frames {
            if isSimulated { replayFrame = frame.cgImage }
            guard let analysis else { continue }
            let state = Self.signposter.beginInterval("analyze")
            let start = ContinuousClock.now
            let metrics = await analysis.analyze(frame)
            Self.signposter.endInterval("analyze", state)
            let now = ContinuousClock.now
            analysisTime = now - start
            guidance = coach.update(CaptureAssessment(metrics), at: now)
            subjectBounds = metrics.subjectBounds
        }
    }

    func stop() async {
        await feed.stop()
    }

    /// The camera's rotation for the current interface orientation, in degrees.
    private(set) var rotationAngle: CGFloat = 90

    func setRotation(_ angle: CGFloat) {
        rotationAngle = angle
        guard let camera else { return }
        Task { await camera.setRotation(angle) }
    }

    func capture() async -> Data? {
        isCapturing = true
        defer { isCapturing = false }
        do {
            return try await feed.capturePhoto()
        } catch {
            captureError = FriendlyError.message(for: error)
            return nil
        }
    }

    func dismissError() {
        captureError = nil
    }

    /// Loading the model takes a moment; keep it off the main actor. Without
    /// the model (or Metal), the camera still works, just without coaching.
    @concurrent
    private static func makeAnalysis() async -> LiveAnalysis? {
        guard let analyzer = try? FrameAnalyzer() else { return nil }
        let segmenter = try? Segmenters.u2netp(renderer: RenderService(cacheIntermediates: false))
        return LiveAnalysis(analyzer: analyzer, segmenter: segmenter)
    }
}

/// Analyzes frames one at a time, off the main actor. The subject mask is
/// refreshed every few frames: framing changes slowly next to exposure and
/// shake, and the model is the most expensive step.
actor LiveAnalysis {
    static let maskInterval = 3

    private let analyzer: FrameAnalyzer
    private let segmenter: CoreMLSegmenter?
    private var mask: CIImage?
    private var frameIndex = 0

    init(analyzer: FrameAnalyzer, segmenter: CoreMLSegmenter?) {
        self.analyzer = analyzer
        self.segmenter = segmenter
    }

    func analyze(_ frame: CIImage) async -> FrameMetrics {
        if frameIndex % Self.maskInterval == 0, let segmenter {
            mask = try? await segmenter.liveMask(for: frame)
        }
        frameIndex += 1
        return analyzer.analyze(frame, subjectMask: mask)
    }
}
