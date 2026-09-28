import CleanCutKit
import CoreImage
import MetalKit
import SwiftUI
import os

/// What the canvas should show. A plain value: SwiftUI hands a new one to the
/// renderer on every update, and the renderer redraws only when it changed.
struct CanvasScene: Equatable {
    enum Mode: Equatable {
        /// The finished studio shot in the selected format.
        case studio
        /// The original photo with objects outlined for tap-to-select.
        case select
        /// The untouched original (press-and-hold compare).
        case original
    }

    var mode: Mode
    var recipe: Recipe
    /// When the cutout "lift" animation started; `nil` once finished.
    var revealStart: Date?

    static func == (lhs: CanvasScene, rhs: CanvasScene) -> Bool {
        lhs.mode == rhs.mode && lhs.recipe == rhs.recipe && lhs.revealStart == rhs.revealStart
    }
}

/// Shared layout math for the renderer (pixels) and hit-testing (points), so a
/// tap always lands where the pixels are drawn.
enum CanvasLayout {
    static let padding: CGFloat = 20

    /// Where content of `contentSize` is drawn inside a view of `viewSize`, in the
    /// view's own units, top-left origin.
    static func contentRect(for contentSize: CGSize, in viewSize: CGSize, scale: CGFloat = 1) -> CGRect {
        let inset = padding * scale
        let bounds = CGRect(origin: .zero, size: viewSize).insetBy(dx: inset, dy: inset)
        return ViewportMath.aspectFit(contentSize, in: bounds).integral
    }
}

/// The live preview: an `MTKView` drawn by Core Image through the shared
/// Metal-backed `CIContext`.
struct CanvasView: UIViewRepresentable {
    let photo: PreparedPhoto
    let scene: CanvasScene
    let renderer: RenderService
    let stats: FrameStats

    func makeCoordinator() -> PreviewRenderer {
        PreviewRenderer(renderer: renderer, stats: stats)
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: renderer.device)
        view.delegate = context.coordinator
        // Core Image writes into the drawable with compute, so it can't be framebuffer-only.
        view.framebufferOnly = false
        view.colorPixelFormat = .bgra8Unorm
        view.autoResizeDrawable = true
        view.preferredFramesPerSecond = 120
        view.enableSetNeedsDisplay = true
        view.isPaused = true
        view.isOpaque = true
        view.backgroundColor = UIColor(named: "CanvasBackground")
        view.accessibilityIgnoresInvertColors = true
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.update(photo: photo, scene: scene, accent: UIColor.tintColor(for: view.traitCollection), view: view)
    }
}

private extension UIColor {
    static func tintColor(for traits: UITraitCollection) -> UIColor {
        (UIColor(named: "AccentColor") ?? .systemTeal).resolvedColor(with: traits)
    }
}

/// Draws frames. Redraws on demand when the scene changes, and runs a display
/// link only while something animates (the lift, or the pulsing selection glow).
final class PreviewRenderer: NSObject, MTKViewDelegate {
    private let renderer: RenderService
    private let stats: FrameStats
    private var photo: PreparedPhoto?
    private var scene: CanvasScene?
    private var accent = RGBA.black
    private var background = RGBA.white
    private let signposter = OSSignposter(subsystem: "dev.sohrab.cleancut", category: "Preview")

    static let revealDuration: TimeInterval = 0.7

    init(renderer: RenderService, stats: FrameStats) {
        self.renderer = renderer
        self.stats = stats
    }

    func update(photo: PreparedPhoto, scene: CanvasScene, accent: UIColor, view: MTKView) {
        let background = RGBA(uiColor: (view.backgroundColor ?? .white).resolvedColor(with: view.traitCollection))
        let accent = RGBA(uiColor: accent)
        let changed = scene != self.scene || photo.workingImage !== self.photo?.workingImage
            || accent != self.accent || background != self.background
        self.photo = photo
        self.scene = scene
        self.accent = accent
        self.background = background

        let animating = scene.mode == .select || isRevealing(scene, at: .now)
        view.isPaused = !animating
        view.enableSetNeedsDisplay = !animating
        if changed, !animating { view.setNeedsDisplay() }
    }

    private func isRevealing(_ scene: CanvasScene, at date: Date) -> Bool {
        guard let start = scene.revealStart else { return false }
        return date.timeIntervalSince(start) < Self.revealDuration
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        view.setNeedsDisplay()
    }

    func draw(in view: MTKView) {
        guard let photo, let scene,
              let drawable = view.currentDrawable,
              let buffer = renderer.commandQueue?.makeCommandBuffer()
        else { return }

        let state = signposter.beginInterval("Frame")
        let cpuStart = CACurrentMediaTime()
        let size = view.drawableSize
        let scale = view.contentScaleFactor
        let image = composeFrame(photo: photo, scene: scene, drawableSize: size, scale: scale)
            .composited(over: CIImage(color: background.ciColor))
            .cropped(to: CGRect(origin: .zero, size: size))

        let texture = drawable.texture
        let destination = CIRenderDestination(
            width: Int(size.width),
            height: Int(size.height),
            pixelFormat: view.colorPixelFormat,
            commandBuffer: buffer
        ) { texture }
        destination.colorSpace = ColorSpaces.sRGB
        _ = try? renderer.context.startTask(toRender: image, to: destination)

        let cpuTime = CACurrentMediaTime() - cpuStart
        let stats = self.stats
        buffer.addCompletedHandler { buffer in
            stats.record(cpu: cpuTime, gpu: buffer.gpuEndTime - buffer.gpuStartTime)
        }
        buffer.present(drawable)
        buffer.commit()
        signposter.endInterval("Frame", state)

        // Stop the display link once the lift animation is over.
        if scene.mode != .select, !isRevealing(scene, at: .now), !view.isPaused {
            view.isPaused = true
            view.enableSetNeedsDisplay = true
        }
    }

    // MARK: - Frame composition

    private func composeFrame(photo: PreparedPhoto, scene: CanvasScene, drawableSize: CGSize, scale: CGFloat) -> CIImage {
        switch scene.mode {
        case .original:
            return photoFrame(photo: photo, drawableSize: drawableSize, scale: scale)
        case .select:
            let rect = CanvasLayout.contentRect(for: photo.proxySource.extent.size, in: drawableSize, scale: scale)
            let pulse = 0.5 + 0.5 * sin(Date.now.timeIntervalSinceReferenceDate * 2 * .pi / 1.6)
            return SelectionOverlay
                .makeImage(photo: photo, selection: scene.recipe.selectedInstances, outputSize: rect.size, accent: accent, pulse: pulse)
                .transformed(by: placement(of: rect, in: drawableSize))
        case .studio:
            let studio = studioFrame(photo: photo, recipe: scene.recipe, drawableSize: drawableSize, scale: scale)
            guard let start = scene.revealStart else { return studio }
            let t = min(1, Date.now.timeIntervalSince(start) / Self.revealDuration)
            return reveal(from: photoFrame(photo: photo, drawableSize: drawableSize, scale: scale), to: studio, progress: t, drawableSize: drawableSize)
        }
    }

    private func photoFrame(photo: PreparedPhoto, drawableSize: CGSize, scale: CGFloat) -> CIImage {
        let source = photo.proxySource
        let rect = CanvasLayout.contentRect(for: source.extent.size, in: drawableSize, scale: scale)
        let fit = CGAffineTransform(scaleX: rect.width / source.extent.width, y: rect.height / source.extent.height)
        return source
            .resampled(by: fit)
            .transformed(by: placement(of: rect, in: drawableSize))
    }

    private func studioFrame(photo: PreparedPhoto, recipe: Recipe, drawableSize: CGSize, scale: CGFloat) -> CIImage {
        let preset = recipe.preset
        let rect = CanvasLayout.contentRect(for: preset.pixelSize, in: drawableSize, scale: scale)
        guard rect.width >= 1, rect.height >= 1,
              let inputs = photo.previewInputs(selection: recipe.selectedInstances)
        else {
            return CIImage.empty()
        }
        var output = Pipeline.makeImage(inputs, recipe: recipe, outputSize: rect.size)
        if recipe.effectiveBackground == .transparent {
            output = output.composited(over: checkerboard(size: rect.size, scale: scale))
        }
        let card = output.transformed(by: placement(of: rect, in: drawableSize))
        return card.composited(over: cardShadow(for: rect, in: drawableSize, scale: scale))
    }

    /// Cross-fade from the photo to the studio shot while the card settles from
    /// 96% to full size — the cutout "lifts" out of its original surroundings.
    private func reveal(from photo: CIImage, to studio: CIImage, progress: Double, drawableSize: CGSize) -> CIImage {
        let eased = 1 - pow(1 - progress, 3)
        let settle = 0.96 + 0.04 * eased
        let center = CGPoint(x: drawableSize.width / 2, y: drawableSize.height / 2)
        let zoom = CGAffineTransform(translationX: center.x, y: center.y)
            .scaledBy(x: settle, y: settle)
            .translatedBy(x: -center.x, y: -center.y)
        let fading = photo.applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1 - eased),
        ])
        return fading.composited(over: studio.transformed(by: zoom))
    }

    /// Top-left-origin rect (pixels) → Core Image translation (bottom-left origin).
    private func placement(of rect: CGRect, in drawableSize: CGSize) -> CGAffineTransform {
        CGAffineTransform(translationX: rect.minX, y: drawableSize.height - rect.maxY)
    }

    private func cardShadow(for rect: CGRect, in drawableSize: CGSize, scale: CGFloat) -> CIImage {
        let ciRect = CGRect(x: rect.minX, y: drawableSize.height - rect.maxY, width: rect.width, height: rect.height)
        return CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0.12))
            .cropped(to: ciRect.offsetBy(dx: 0, dy: -2 * scale))
            .applyingGaussianBlur(sigma: 6 * scale)
    }

    private func checkerboard(size: CGSize, scale: CGFloat) -> CIImage {
        CIFilter(name: "CICheckerboardGenerator", parameters: [
            "inputColor0": CIColor(red: 1, green: 1, blue: 1),
            "inputColor1": CIColor(red: 0.9, green: 0.9, blue: 0.92),
            "inputWidth": 10 * scale,
        ])!.outputImage!.cropped(to: CGRect(origin: .zero, size: size))
    }
}

/// Frame timing, written from Metal's completion thread and read by the HUD.
final class FrameStats: Sendable {
    struct Snapshot: Sendable {
        var frames = 0
        var lastCPU: TimeInterval = 0
        var lastGPU: TimeInterval = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: Snapshot())

    nonisolated func record(cpu: TimeInterval, gpu: TimeInterval) {
        state.withLock {
            $0.frames += 1
            $0.lastCPU = cpu
            $0.lastGPU = gpu
        }
    }

    nonisolated var snapshot: Snapshot { state.withLock { $0 } }
}

extension RGBA {
    init(uiColor: UIColor) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}
