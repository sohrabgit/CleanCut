import AVFoundation
import CoreImage
import os

/// The device camera: preview, analysis frames and full-resolution photos.
///
/// An actor running on its own serial queue. Session configuration and
/// `startRunning()` block for hundreds of milliseconds; on the default
/// executor they'd tie up a thread of Swift's small cooperative pool. The
/// video output delivers on the same queue.
actor CameraEngine: CameraFeed {
    nonisolated let frames: AsyncStream<CIImage>
    /// For the preview layer, the only thing the main actor touches.
    nonisolated let preview: PreviewSession

    private let queue = DispatchSerialQueue(label: "dev.sohrab.cleancut.camera", qos: .userInitiated)
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    private let frameReceiver: FrameReceiver
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private var isConfigured = false
    /// Photo delegates are weak references in AVFoundation; keep them alive.
    private var photoReceivers: [Int64: PhotoReceiver] = [:]
    private var session: AVCaptureSession { preview.session }

    /// A back camera exists and this isn't an iPad app on a Mac (where the
    /// only camera faces the user).
    static var isAvailable: Bool {
        AVCaptureDevice.default(for: .video) != nil && !ProcessInfo.processInfo.isiOSAppOnMac
    }

    init() {
        let (frames, continuation) = AsyncStream.makeStream(of: CIImage.self, bufferingPolicy: .bufferingNewest(1))
        self.frames = frames
        self.frameReceiver = FrameReceiver(continuation: continuation)
        self.preview = PreviewSession(session: AVCaptureSession())
    }

    func start() async throws {
        guard await Self.requestAccess() else { throw CameraFeedError.accessDenied }
        if !isConfigured { try configure() }
        session.startRunning()
    }

    func stop() async {
        session.stopRunning()
    }

    /// Rotates frames and photos to match the interface (`0`, `90`, `180`, `270`).
    func setRotation(_ angle: CGFloat) {
        for connection in [videoOutput.connection(with: .video), photoOutput.connection(with: .video)] {
            if let connection, connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        }
    }

    func capturePhoto() async throws -> Data {
        let settings = photoOutput.availablePhotoCodecTypes.contains(.hevc)
            ? AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            : AVCapturePhotoSettings()
        settings.photoQualityPrioritization = .balanced
        let id = settings.uniqueID
        defer { photoReceivers[id] = nil }
        return try await withCheckedThrowingContinuation { continuation in
            let receiver = PhotoReceiver(continuation: continuation)
            photoReceivers[id] = receiver
            photoOutput.capturePhoto(with: settings, delegate: receiver)
        }
    }

    private static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .video)
        default: false
        }
    }

    private func configure() throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(for: .video)
        else { throw CameraFeedError.unavailable }
        let input = try AVCaptureDeviceInput(device: device)

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard session.canAddInput(input), session.canAddOutput(photoOutput), session.canAddOutput(videoOutput) else {
            throw CameraFeedError.unavailable
        }
        session.addInput(input)
        session.addOutput(photoOutput)
        session.addOutput(videoOutput)

        photoOutput.maxPhotoQualityPrioritization = .balanced
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.setSampleBufferDelegate(frameReceiver, queue: queue)
        isConfigured = true
        setRotation(90) // portrait until the view says otherwise
    }
}

/// `AVCaptureSession` isn't annotated `Sendable`. The main actor only hands it
/// to an `AVCaptureVideoPreviewLayer`, which AVFoundation supports while the
/// session is configured and started on another queue (Apple's AVCam sample
/// does the same); every other use stays inside `CameraEngine`.
nonisolated struct PreviewSession: @unchecked Sendable {
    let session: AVCaptureSession
}

/// Turns video sample buffers into analysis frames, throttled to ~15 fps:
/// coaching doesn't need more, and the phone stays cool.
private nonisolated final class FrameReceiver: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, Sendable {
    static let minInterval = 1.0 / 15

    private let continuation: AsyncStream<CIImage>.Continuation
    private let lastFrameTime = OSAllocatedUnfairLock(initialState: -Double.infinity)

    init(continuation: AsyncStream<CIImage>.Continuation) {
        self.continuation = continuation
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let time = sampleBuffer.presentationTimeStamp.seconds
        let isDue = lastFrameTime.withLock { last in
            guard time - last >= Self.minInterval else { return false }
            last = time
            return true
        }
        guard isDue, let buffer = sampleBuffer.imageBuffer else { return }
        continuation.yield(CIImage(cvImageBuffer: buffer))
    }

    deinit {
        continuation.finish()
    }
}

/// Delivers one photo's encoded data (HEIC where supported).
private nonisolated final class PhotoReceiver: NSObject, AVCapturePhotoCaptureDelegate, Sendable {
    private let continuation: CheckedContinuation<Data, any Error>

    init(continuation: CheckedContinuation<Data, any Error>) {
        self.continuation = continuation
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: (any Error)?) {
        if let data = photo.fileDataRepresentation() {
            continuation.resume(returning: data)
        } else {
            continuation.resume(throwing: error ?? CameraFeedError.captureFailed)
        }
    }
}
