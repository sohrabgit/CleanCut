import AVFoundation
import CleanCutKit
import SwiftUI

/// Guided capture: a live camera that coaches before the shutter (sharpness,
/// light, glare, framing) so the photo is ready for a clean cutout. It
/// advises and never blocks: the shutter always works.
struct CaptureView: View {
    let onCapture: (Data) -> Void

    @State private var model = CaptureModel()
    @State private var isFlashing = false
    @State private var lastAnnouncement: ContinuousClock.Instant?
    @AppStorage("showPerformanceHUD") private var showHUD = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            topBar
            switch model.phase {
            case .accessDenied:
                accessDenied
            case .failed(let message):
                ContentUnavailableView("Camera unavailable", systemImage: "video.slash", description: Text(message))
            case .starting, .live:
                camera
            }
        }
        .background(Color.black.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .task { await model.run() }
        .onDisappear { Task { await model.stop() } }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureSession.wasInterruptedNotification)) { _ in
            model.isInterrupted = true
        }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureSession.interruptionEndedNotification)) { _ in
            model.isInterrupted = false
        }
        .onChange(of: model.guidance) { old, new in
            if old.tip != new.tip || old.isReady != new.isReady { announce(new) }
        }
        .alert("Couldn't take the photo", isPresented: Binding(
            get: { model.captureError != nil },
            set: { if !$0 { model.dismissError() } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.captureError ?? "")
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            Button("Close", systemImage: "xmark") { dismiss() }
                .buttonStyle(.toolbarIcon)
                .keyboardShortcut(.cancelAction)
            Spacer()
            if model.isSimulated {
                Label("Simulated camera", systemImage: "camera.metering.unknown")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, Tokens.Spacing.s)
                    .padding(.vertical, Tokens.Spacing.xxs + 2)
                    .background(.fill.tertiary, in: Capsule())
                    .accessibilityHint("There is no camera here, so a staged scene plays instead.")
            }
        }
        .padding(.horizontal, Tokens.Spacing.s)
        .frame(height: 52)
    }

    private var camera: some View {
        VStack(spacing: Tokens.Spacing.m) {
            Spacer(minLength: 0)
            viewfinder
                .padding(.horizontal, Tokens.Spacing.xs)
                .layoutPriority(1)
            Spacer(minLength: 0)
            checklist
                .padding(.horizontal, Tokens.Spacing.m)
            shutter
        }
        .padding(.bottom, Tokens.Spacing.s)
    }

    private var accessDenied: some View {
        ContentUnavailableView {
            Label("Camera access is off", systemImage: "camera")
        } description: {
            Text("Allow camera access in Settings to photograph products with live tips.")
        } actions: {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(.primary)
            .frame(maxWidth: 280)
        }
    }

    // MARK: - Viewfinder

    /// 4:3 like the photo, so "cut off" means cut off in the picture too.
    private var aspectRatio: CGFloat {
        let isLandscape = !model.isSimulated && (model.rotationAngle == 0 || model.rotationAngle == 180)
        return isLandscape ? 4 / 3 : 3 / 4
    }

    private var viewfinder: some View {
        ZStack {
            if let preview = model.preview {
                CameraPreview(session: preview, isRunning: model.phase == .live, onRotation: model.setRotation)
            } else if let frame = model.replayFrame {
                Image(decorative: frame, scale: 1).resizable()
            } else {
                Color.black
            }
            SubjectBrackets(bounds: model.subjectBounds, isFramed: model.guidance.passes(.framing) == true)
                .animation(reduceMotion ? nil : Tokens.Motion.snappy, value: model.subjectBounds)
            if model.isInterrupted {
                Label("Camera paused", systemImage: "pause.circle")
                    .font(.headline)
                    .padding(Tokens.Spacing.m)
                    .background(.regularMaterial, in: .rect(cornerRadius: Tokens.Radius.medium))
            }
            if isFlashing {
                Color.white.allowsHitTesting(false)
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .clipShape(.rect(cornerRadius: Tokens.Radius.medium))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.isSimulated ? "Simulated camera preview" : "Camera preview")
        .accessibilityAddTraits(.isImage)
        .overlay(alignment: .bottom) { tip }
        .overlay(alignment: .topLeading) {
            if showHUD, let time = model.analysisTime {
                Text("Analysis \(time.milliseconds, specifier: "%.1f") ms · mask every \(LiveAnalysis.maskInterval) frames")
                    .font(.caption2.monospacedDigit())
                    .padding(.horizontal, Tokens.Spacing.xs)
                    .padding(.vertical, Tokens.Spacing.xxs)
                    .background(.black.opacity(0.6), in: .rect(cornerRadius: Tokens.Radius.small))
                    .padding(Tokens.Spacing.xs)
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private var tip: some View {
        if model.phase == .live, let text = tipText {
            HintCapsule(systemImage: model.guidance.tip?.systemImage ?? "checkmark.circle.fill", text: text)
                .id(text)
                .padding(.horizontal, Tokens.Spacing.s)
                .animation(reduceMotion ? nil : Tokens.Motion.snappy, value: text)
        }
    }

    /// `nil` until the first frame has been analyzed.
    private var tipText: String? {
        if let issue = model.guidance.tip { return issue.tip }
        return model.guidance.isReady ? CaptureIssue.readyTip : nil
    }

    // MARK: - Checks and shutter

    private var checklist: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Tokens.Spacing.xs) { pills }
            Grid(horizontalSpacing: Tokens.Spacing.xs, verticalSpacing: Tokens.Spacing.xs) {
                GridRow { pill(.framing); pill(.light) }
                GridRow { pill(.sharpness); pill(.glare) }
            }
        }
    }

    @ViewBuilder
    private var pills: some View {
        ForEach(CaptureCheck.allCases, id: \.self) { pill($0) }
    }

    private func pill(_ check: CaptureCheck) -> some View {
        CheckPill(title: check.title, passes: model.phase == .live ? model.guidance.passes(check) : nil)
    }

    private var shutter: some View {
        Button(action: takePhoto) {
            Text("Take photo")
        }
        .buttonStyle(ShutterButtonStyle(isReady: model.guidance.isReady))
        .animation(reduceMotion ? nil : Tokens.Motion.snappy, value: model.guidance.isReady)
        .disabled(model.phase != .live || model.isCapturing)
        .accessibilityIdentifier("shutter")
        .accessibilityValue(model.guidance.isReady ? "Ready" : (tipText ?? ""))
        .sensoryFeedback(trigger: model.guidance.isReady) { wasReady, isReady in
            isReady && !wasReady ? .success : nil
        }
    }

    private func takePhoto() {
        Task {
            if !reduceMotion {
                isFlashing = true
                withAnimation(.easeOut(duration: 0.3)) { isFlashing = false }
            }
            guard let data = await model.capture() else { return }
            onCapture(data)
            dismiss()
        }
    }

    /// Tips are already steady (the coach waits 0.4 s before changing one);
    /// VoiceOver additionally gets at most one every 2 s.
    private func announce(_ guidance: CaptureGuidance) {
        guard UIAccessibility.isVoiceOverRunning, let text = tipText else { return }
        let now = ContinuousClock.now
        if let lastAnnouncement, now - lastAnnouncement < .seconds(2) { return }
        lastAnnouncement = now
        AccessibilityNotification.Announcement(text).post()
    }
}

// MARK: - Components

/// One check's state: symbol and text, never color alone.
private struct CheckPill: View {
    let title: String
    let passes: Bool?

    var body: some View {
        Label {
            Text(title).lineLimit(1)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(passes == true ? AnyShapeStyle(.accent) : AnyShapeStyle(.secondary))
        }
        .font(.footnote.weight(.semibold))
        .padding(.horizontal, Tokens.Spacing.s)
        .padding(.vertical, Tokens.Spacing.xs)
        .frame(maxWidth: .infinity)
        .background(.fill.tertiary, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityValue(passes.map { $0 ? "OK" : "Needs attention" } ?? "Checking")
    }

    private var symbol: String {
        switch passes {
        case true?: "checkmark.circle.fill"
        case false?: "exclamationmark.circle"
        case nil: "circle.dotted"
        }
    }
}

/// The shutter: a white disc in a ring that turns accent when every check passes.
private struct ShutterButtonStyle: ButtonStyle {
    let isReady: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            Circle()
                .strokeBorder(isReady ? Color.accentColor : .white, lineWidth: 5)
            Circle()
                .fill(.white)
                .padding(9)
                .scaleEffect(configuration.isPressed ? 0.9 : 1)
            configuration.label.hidden()
        }
        .frame(width: 76, height: 76)
        .opacity(isEnabled ? 1 : 0.5)
        .contentShape(Circle())
        .animation(Tokens.Motion.snappy, value: configuration.isPressed)
    }
}

/// Corner brackets around the detected product.
private struct SubjectBrackets: View {
    /// Normalized, top-left origin.
    let bounds: CGRect?
    let isFramed: Bool

    var body: some View {
        GeometryReader { geometry in
            if let bounds {
                let rect = CGRect(
                    x: bounds.minX * geometry.size.width, y: bounds.minY * geometry.size.height,
                    width: bounds.width * geometry.size.width, height: bounds.height * geometry.size.height
                ).insetBy(dx: -6, dy: -6)
                BracketShape()
                    .stroke(isFramed ? Color.accentColor : .white, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .shadow(color: .black.opacity(0.35), radius: 2)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct BracketShape: Shape {
    func path(in rect: CGRect) -> Path {
        let arm = min(24, 0.25 * min(rect.width, rect.height))
        var path = Path()
        for (corner, dx, dy) in [
            (CGPoint(x: rect.minX, y: rect.minY), 1.0, 1.0),
            (CGPoint(x: rect.maxX, y: rect.minY), -1.0, 1.0),
            (CGPoint(x: rect.minX, y: rect.maxY), 1.0, -1.0),
            (CGPoint(x: rect.maxX, y: rect.maxY), -1.0, -1.0),
        ] {
            path.move(to: CGPoint(x: corner.x, y: corner.y + dy * arm))
            path.addLine(to: corner)
            path.addLine(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
        }
        return path
    }
}

/// The camera's live preview layer. Aspect-fill in a 4:3 frame, so it shows
/// exactly what the photo will contain.
private struct CameraPreview: UIViewRepresentable {
    let session: PreviewSession
    /// Re-applies the rotation once the session runs (its connection appears then).
    let isRunning: Bool
    let onRotation: (CGFloat) -> Void

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session.session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.onRotation = onRotation
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        view.applyRotation()
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        var onRotation: ((CGFloat) -> Void)?
        private var reportedAngle: CGFloat?

        override func layoutSubviews() {
            super.layoutSubviews()
            applyRotation()
        }

        /// Back-camera rotation for the interface orientation; the sensor's
        /// native orientation is landscape-right.
        func applyRotation() {
            let angle: CGFloat = switch window?.windowScene?.effectiveGeometry.interfaceOrientation ?? .portrait {
            case .landscapeRight: 0
            case .landscapeLeft: 180
            case .portraitUpsideDown: 270
            default: 90
            }
            if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
            if angle != reportedAngle {
                reportedAngle = angle
                // Not during layout: SwiftUI state shouldn't change mid-update.
                let onRotation = onRotation
                Task { onRotation?(angle) }
            }
        }
    }
}
