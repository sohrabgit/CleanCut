import CleanCutKit
import CoreGraphics
import SwiftUI

@Observable
final class EditorModel {
    enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    enum Tool: String, CaseIterable, Identifiable {
        case select, background, shadow, edges

        var id: Self { self }

        var title: String {
            switch self {
            case .select: "Select"
            case .background: "Background"
            case .shadow: "Shadow"
            case .edges: "Edges"
            }
        }

        var systemImage: String {
            switch self {
            case .select: "hand.tap"
            case .background: "paintpalette"
            case .shadow: "shadow"
            case .edges: "wand.and.stars"
            }
        }
    }

    let source: PhotoSource
    let renderer: RenderService
    let stats = FrameStats()

    private(set) var phase: Phase = .loading
    /// The decoded photo, shown under the scanning shimmer while segmenting.
    private(set) var originalPreview: UIImage?
    private(set) var photo: PreparedPhoto?
    private(set) var revealStart: Date?

    /// The live recipe. Sliders write here continuously; `commit()` records an
    /// undo step when a gesture ends.
    var recipe: Recipe
    private var history: History<Recipe>

    var tool: Tool = .background
    var isComparing = false

    /// Each editing session owns its render context, released when the editor
    /// closes: a long-lived context accumulates GPU resources across photos
    /// (docs/DECISIONS.md, 006).
    init(source: PhotoSource, renderer: RenderService = RenderService()) {
        self.source = source
        self.renderer = renderer
        let style = StyleStore.load()
        self.recipe = style
        self.history = History(style)
    }

    // MARK: - Loading

    func load() async {
        phase = .loading
        do {
            let image = try await Self.decode(source)
            originalPreview = UIImage(cgImage: image)
            let photo = try await prepare(image)
            self.photo = photo
            phase = .ready
            revealStart = .now
            try? await Task.sleep(for: .seconds(PreviewRenderer.revealDuration))
            revealStart = nil
        } catch is CancellationError {
            return
        } catch {
            phase = .failed(FriendlyError.message(for: error))
        }
    }

    @concurrent
    private static func decode(_ source: PhotoSource) async throws -> CGImage {
        switch source {
        case .data(let data): try ImageLoader.load(data: data)
        case .sample(let sample): try ImageLoader.load(url: sample.imageURL)
        }
    }

    private func prepare(_ image: CGImage) async throws -> PreparedPhoto {
        do {
            return try await PreparedPhoto.prepare(image, segmenter: VisionSegmenter(), renderer: renderer)
        } catch SegmentationError.unavailable {
            // Simulator: samples ship with masks precomputed by Vision on a Mac.
            guard case .sample(let sample) = source, !sample.maskURLs.isEmpty else {
                throw SegmentationError.unavailable("")
            }
            let segmenter = MaskSegmenter(name: "Bundled masks", masks: sample.masks(), renderer: renderer)
            return try await PreparedPhoto.prepare(image, segmenter: segmenter, renderer: renderer)
        }
    }

    // MARK: - Canvas

    var canvasScene: CanvasScene {
        let mode: CanvasScene.Mode = isComparing ? .original : (tool == .select ? .select : .studio)
        return CanvasScene(mode: mode, recipe: recipe, revealStart: revealStart)
    }

    /// True when the product runs off the photo's edge; the cut there will be
    /// hard, so the editor suggests reshooting with some space around it.
    var subjectTouchesEdge: Bool {
        guard let photo, let bounds = photo.segmentation.subjectBounds(for: recipe.selectedInstances) else { return false }
        let image = CGRect(origin: .zero, size: photo.segmentation.imageSize)
        let margin = max(image.width, image.height) * 0.004
        return bounds.minX <= margin || bounds.minY <= margin
            || bounds.maxX >= image.maxX - margin || bounds.maxY >= image.maxY - margin
    }

    // MARK: - Selection

    var instances: [Int] { photo?.instances ?? [] }

    func isSelected(_ instance: Int) -> Bool {
        recipe.selectedInstances?.contains(instance) ?? true
    }

    /// Handles a tap on the canvas in Select mode. Returns the toggled instance.
    @discardableResult
    func handleTap(at point: CGPoint, in viewSize: CGSize) -> Int? {
        guard let photo, tool == .select else { return nil }
        let rect = CanvasLayout.contentRect(for: photo.proxySource.extent.size, in: viewSize)
        guard let normalized = ViewportMath.normalizedPoint(point, inImageRect: rect),
              let instance = InstanceHitTester.instance(at: normalized, in: photo.segmentation.labelMap)
        else { return nil }
        return toggle(instance) ? instance : nil
    }

    /// Includes or excludes an object. Refuses to exclude the last one.
    @discardableResult
    func toggle(_ instance: Int) -> Bool {
        let all = Set(instances)
        var selected = recipe.selectedInstances ?? all
        if selected.contains(instance) {
            guard selected.count > 1 else { return false }
            selected.remove(instance)
        } else {
            selected.insert(instance)
        }
        update { $0.selectedInstances = selected == all ? nil : selected }
        let state = selected.contains(instance) ? "included" : "excluded"
        AccessibilityNotification.Announcement("Object \(instance) \(state)").post()
        return true
    }

    func selectAll() {
        update { $0.selectedInstances = nil }
    }

    // MARK: - Recipe & undo

    /// Applies a discrete change (chip, swatch, toggle) as one undo step.
    func update(_ change: (inout Recipe) -> Void) {
        change(&recipe)
        commit()
    }

    /// Records the live recipe as an undo step (end of a slider drag).
    func commit() {
        history.commit(recipe)
        StyleStore.save(recipe)
    }

    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }

    func undo() {
        if let value = history.undo() { recipe = value }
    }

    func redo() {
        if let value = history.redo() { recipe = value }
    }
}
