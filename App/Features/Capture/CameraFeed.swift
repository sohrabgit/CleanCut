import CleanCutKit
import CoreImage
import Foundation
import ImageIO
import os
import UniformTypeIdentifiers

/// Where guided capture's frames come from: the camera, or the replay scene
/// where there is none. Everything downstream (analysis, coaching, UI) is the
/// same for both, so the Simulator exercises the real path.
nonisolated protocol CameraFeed: Sendable {
    /// Upright frames for analysis, at most ~15 per second. Only the newest is
    /// buffered, so a slow consumer drops frames instead of holding on to
    /// camera buffers (which starves the capture pool).
    var frames: AsyncStream<CIImage> { get }
    func start() async throws
    func stop() async
    /// A full-resolution photo of what's in front of the camera now.
    func capturePhoto() async throws -> Data
}

enum CameraFeedError: Error {
    case accessDenied
    case unavailable
    case captureFailed
}

/// A camera that films `ReplayScene`: the Simulator, UI tests and the demo.
///
/// Plays the scene's timeline, or holds one scenario when launched with
/// `-captureReplay <scenario>` (deterministic screenshots).
nonisolated final class ReplayFeed: CameraFeed {
    let frames: AsyncStream<CIImage>
    private let continuation: AsyncStream<CIImage>.Continuation
    private let scenario: CaptureScenario?
    private let scene = ReplayScene()
    /// Renders the scene's camera-encoded values as they are, like a sensor.
    private let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull(), .name: "CleanCut.replay"])
    private let state = OSAllocatedUnfairLock<(task: Task<Void, Never>?, latest: CGImage?)>(initialState: (nil, nil))

    init(scenario: CaptureScenario?) {
        self.scenario = scenario
        (frames, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    func start() async throws {
        let task = Task { [weak self] in
            let start = ContinuousClock.now
            while !Task.isCancelled, let self {
                let time = (ContinuousClock.now - start) / .seconds(1)
                self.emitFrame(at: time)
                try? await Task.sleep(for: .milliseconds(66))
            }
        }
        state.withLock { $0.task?.cancel(); $0.task = task }
    }

    func stop() async {
        state.withLock { $0.task?.cancel(); $0.task = nil }
    }

    func capturePhoto() async throws -> Data {
        guard let image = state.withLock({ $0.latest }), let data = Self.jpeg(image) else {
            throw CameraFeedError.captureFailed
        }
        return data
    }

    private func emitFrame(at time: Double) {
        let frame = scene.frame(scenario ?? ReplayScene.scenario(at: time), time: time)
        guard let image = context.createCGImage(frame, from: scene.extent, format: .RGBA8, colorSpace: ColorSpaces.sRGB) else { return }
        state.withLock { $0.latest = image }
        continuation.yield(CIImage(cgImage: image))
    }

    private static func jpeg(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    deinit {
        state.withLock { $0.task?.cancel() }
        continuation.finish()
    }
}
