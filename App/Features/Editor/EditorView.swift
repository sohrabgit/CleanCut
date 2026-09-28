import CleanCutKit
import SwiftUI

struct EditorView: View {
    @State private var model: EditorModel
    @State private var isExporting = false
    @State private var dismissedEdgeTip = false
    @AppStorage("showPerformanceHUD") private var showHUD = false
    @AppStorage("hasSeenSelectHint") private var hasSeenSelectHint = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass

    init(source: PhotoSource) {
        _model = State(initialValue: EditorModel(source: source))
    }

    var body: some View {
        Group {
            if sizeClass == .regular {
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        topBar
                        canvasArea
                    }
                    if model.phase == .ready {
                        Divider().ignoresSafeArea()
                        inspector
                            .frame(width: 360)
                            .transition(.move(edge: .trailing))
                    }
                }
            } else {
                VStack(spacing: 0) {
                    topBar
                    canvasArea
                    if model.phase == .ready {
                        FormatBar(model: model)
                            .padding(.vertical, Tokens.Spacing.xs)
                        ToolTray(model: model)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
        }
        .background(Color.canvasBackground.ignoresSafeArea())
        .animation(Tokens.Motion.spring, value: model.phase)
        .task { await model.load() }
        .sheet(isPresented: $isExporting) {
            ExportSheet(model: model)
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: Tokens.Spacing.xs) {
            Button("Close", systemImage: "xmark") { dismiss() }
                .buttonStyle(.toolbarIcon)
                .keyboardShortcut(.cancelAction)

            Spacer()

            if model.phase == .ready {
                Button("Undo", systemImage: "arrow.uturn.backward") { model.undo() }
                    .buttonStyle(.toolbarIcon)
                    .disabled(!model.canUndo)
                    .keyboardShortcut("z", modifiers: .command)
                Button("Redo", systemImage: "arrow.uturn.forward") { model.redo() }
                    .buttonStyle(.toolbarIcon)
                    .disabled(!model.canRedo)
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                CompareButton(isComparing: $model.isComparing)

                Button {
                    isExporting = true
                } label: {
                    Text("Export")
                        .font(.headline)
                        .padding(.horizontal, Tokens.Spacing.m)
                        .frame(height: 36)
                        .background(Color.accentColor, in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .frame(minHeight: Tokens.Size.hitTarget)
                .keyboardShortcut("e", modifiers: .command)
                .padding(.leading, Tokens.Spacing.xxs)
            }
        }
        .padding(.horizontal, Tokens.Spacing.s)
        .frame(height: 52)
    }

    // MARK: - Canvas

    @ViewBuilder
    private var canvasArea: some View {
        ZStack {
            switch model.phase {
            case .loading:
                LoadingCanvas(preview: model.originalPreview)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't cut out this photo", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Choose Another Photo") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }
            case .ready:
                if let photo = model.photo {
                    readyCanvas(photo)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func readyCanvas(_ photo: PreparedPhoto) -> some View {
        GeometryReader { geometry in
            CanvasView(photo: photo, scene: model.canvasScene, renderer: model.renderer, stats: model.stats)
                .contentShape(Rectangle())
                .onTapGesture { location in
                    if model.handleTap(at: location, in: geometry.size) != nil {
                        hasSeenSelectHint = true
                    }
                }
                .accessibilityElement()
                .accessibilityLabel(canvasAccessibilityLabel)
                .accessibilityAddTraits(.isImage)
        }
        .overlay(alignment: .bottom) { canvasHints }
        .overlay(alignment: .topLeading) {
            if showHUD { PerformanceHUD(stats: model.stats).padding(Tokens.Spacing.m) }
        }
        .sensoryFeedback(.selection, trigger: model.recipe.selectedInstances)
    }

    private var canvasAccessibilityLabel: String {
        switch model.canvasScene.mode {
        case .original: "Original photo"
        case .select: "Photo with \(model.instances.count) detected objects. Use the object buttons below to include or exclude them."
        case .studio: "Studio preview, \(model.recipe.preset.name) format"
        }
    }

    @ViewBuilder
    private var canvasHints: some View {
        if model.tool == .select, !hasSeenSelectHint {
            HintCapsule(systemImage: "hand.tap", text: "Tap objects to include or exclude them")
        } else if model.tool != .select, model.subjectTouchesEdge, !dismissedEdgeTip {
            HintCapsule(systemImage: "crop", text: "Tip: leave space around the product for cleaner edges") {
                dismissedEdgeTip = true
            }
        }
    }

    // MARK: - Inspector (iPad / Mac)

    private var inspector: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.l) {
            VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                SectionLabel(text: "Format").padding(.horizontal, Tokens.Spacing.m)
                FormatBar(model: model)
            }
            ToolTray(model: model, layout: .inspector)
            Spacer()
        }
        .padding(.top, Tokens.Spacing.m)
        .background(.bar)
    }
}

// MARK: - Supporting views

/// Press and hold to see the original photo.
private struct CompareButton: View {
    @Binding var isComparing: Bool

    var body: some View {
        Image(systemName: isComparing ? "square.split.2x1.fill" : "square.split.2x1")
            .font(.body.weight(.medium))
            .frame(width: Tokens.Size.hitTarget, height: Tokens.Size.hitTarget)
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.01, maximumDistance: 40) {
            } onPressingChanged: { pressing in
                isComparing = pressing
            }
            .accessibilityLabel("Compare with original")
            .accessibilityHint("Press and hold to show the original photo")
            .accessibilityAddTraits(.isButton)
            .sensoryFeedback(.impact(weight: .light), trigger: isComparing)
    }
}

/// While Vision works: the photo with a soft scanning light passing over it.
private struct LoadingCanvas: View {
    let preview: UIImage?
    @State private var phase: CGFloat = -0.3
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Tokens.Spacing.m) {
            if let preview {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFit()
                    .overlay {
                        GeometryReader { geometry in
                            LinearGradient(
                                colors: [.clear, .white.opacity(0.55), .clear],
                                startPoint: .top, endPoint: .bottom
                            )
                            .frame(height: geometry.size.height * 0.25)
                            .offset(y: geometry.size.height * phase)
                            .blendMode(.plusLighter)
                        }
                        .clipped()
                        .opacity(reduceMotion ? 0 : 1)
                    }
                    .padding(CanvasLayout.padding)
                    .transition(.opacity)
            } else {
                Spacer()
            }
            Label("Finding your product…", systemImage: "sparkles")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.bottom, Tokens.Spacing.l)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: false)) {
                phase = 1.05
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct HintCapsule: View {
    let systemImage: String
    let text: String
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: Tokens.Spacing.xs) {
            Image(systemName: systemImage)
            Text(text)
            if let onDismiss {
                Button("Dismiss", systemImage: "xmark", action: onDismiss)
                    .labelStyle(.iconOnly)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.footnote.weight(.medium))
        .padding(.horizontal, Tokens.Spacing.m)
        .padding(.vertical, Tokens.Spacing.xs + 2)
        .background(.regularMaterial, in: Capsule())
        .padding(.bottom, Tokens.Spacing.s)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

private struct PerformanceHUD: View {
    let stats: FrameStats

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let snapshot = stats.snapshot
            Text("GPU \(snapshot.lastGPU * 1000, specifier: "%.1f") ms · CPU \(snapshot.lastCPU * 1000, specifier: "%.1f") ms · \(snapshot.frames) frames")
                .font(.caption2.monospacedDigit())
                .padding(.horizontal, Tokens.Spacing.xs)
                .padding(.vertical, Tokens.Spacing.xxs)
                .background(.black.opacity(0.6), in: .rect(cornerRadius: Tokens.Radius.small))
                .foregroundStyle(.white)
        }
        .accessibilityHidden(true)
    }
}

/// Round, quiet icon buttons for the editor's top bar.
struct ToolbarIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.body.weight(.medium))
            .foregroundStyle(isEnabled ? .primary : .tertiary)
            .frame(width: Tokens.Size.hitTarget, height: Tokens.Size.hitTarget)
            .background(Circle().fill(.fill.quaternary).opacity(configuration.isPressed ? 1 : 0))
            .contentShape(Circle())
    }
}

extension ButtonStyle where Self == ToolbarIconButtonStyle {
    static var toolbarIcon: ToolbarIconButtonStyle { ToolbarIconButtonStyle() }
}
