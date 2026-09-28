import CleanCutKit
import Photos
import PhotosUI
import SwiftUI

@Observable
final class BatchModel {
    enum Phase: Equatable {
        case choosing, ready, running, finished
    }

    enum ItemState: Equatable {
        case waiting
        case processing
        case done
        case failed(String)
    }

    struct Item: Identifiable {
        let id = UUID()
        let source: PhotosPickerItem
        var thumbnail: UIImage?
        var result: UIImage?
        var files: [ExportPreset.ID: URL] = [:]
        var state: ItemState = .waiting
    }

    static let maxPhotos = 50

    private(set) var items: [Item] = []
    private(set) var phase: Phase = .choosing
    private(set) var savedCount: Int?
    var presets: Set<ExportPreset.ID>
    let recipe: Recipe

    private var work: Task<Void, Never>?
    private let outputDirectory: URL

    init() {
        let recipe = StyleStore.load()
        self.recipe = recipe
        self.presets = [recipe.presetID]
        self.outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Batch-\(UUID().uuidString.prefix(8))", isDirectory: true)
    }

    // MARK: - Summary

    var doneCount: Int { items.count { $0.state == .done } }
    var failedCount: Int { items.count { if case .failed = $0.state { true } else { false } } }
    var finishedCount: Int { doneCount + failedCount }

    var styleSummary: String {
        let background: String = switch recipe.background {
        case .solid(let color) where color == .white: "White background"
        case .solid: "Color background"
        case .studioSweep: "Studio background"
        case .transparent: "Transparent"
        }
        let shadow = recipe.shadow.kind == .none ? "no shadow" : "\(recipe.shadow.kind.title.lowercased()) shadow"
        let edges = recipe.edges.cleanEdges ? " · clean edges" : ""
        return "\(background) · \(shadow)\(edges)"
    }

    var selectedPresets: [ExportPreset] {
        ExportPreset.all.filter { presets.contains($0.id) }
    }

    var outputFiles: [URL] {
        items.flatMap { item in selectedPresets.compactMap { item.files[$0.id] } }
    }

    // MARK: - Picking

    func setPhotos(_ picked: [PhotosPickerItem]) {
        guard !picked.isEmpty else { return }
        items = picked.prefix(Self.maxPhotos).map { Item(source: $0) }
        savedCount = nil
        phase = .ready
        Task { await loadThumbnails() }
    }

    private func loadThumbnails() async {
        for index in items.indices {
            let source = items[index].source
            let thumbnail = await Self.thumbnail(for: source)
            guard index < items.count, items[index].source == source else { return }
            items[index].thumbnail = thumbnail
        }
    }

    @concurrent
    private static func thumbnail(for item: PhotosPickerItem) async -> UIImage? {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = try? ImageLoader.load(data: data, maxPixelSize: 300)
        else { return nil }
        return UIImage(cgImage: image)
    }

    // MARK: - Processing

    func start() {
        guard phase != .running, !presets.isEmpty else { return }
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        savedCount = nil
        phase = .running

        let pending = items.filter { $0.state != .done }
        let jobs = pending.map { item in
            let source = item.source
            return BatchJob(id: item.id) { maxPixelSize in
                guard let data = try await source.loadTransferable(type: Data.self) else {
                    throw ImageLoader.LoadError.unreadable
                }
                return try ImageLoader.load(data: data, maxPixelSize: maxPixelSize)
            }
        }
        let processor = BatchProcessor(segmenter: VisionSegmenter())
        let stream = processor.process(jobs, recipe: recipe, presets: selectedPresets, outputDirectory: outputDirectory)

        work = Task {
            for await event in stream {
                apply(event)
            }
            for index in items.indices where items[index].state == .processing {
                items[index].state = .waiting
            }
            phase = .finished
        }
    }

    func cancel() {
        work?.cancel()
    }

    func retryFailed() {
        for index in items.indices {
            if case .failed = items[index].state { items[index].state = .waiting }
        }
        start()
    }

    private func apply(_ event: BatchEvent) {
        switch event {
        case .started(let id):
            update(id) { $0.state = .processing }
        case .finished(let output):
            update(output.jobID) {
                $0.state = .done
                $0.files = output.files
                $0.result = output.thumbnail.map(UIImage.init(cgImage:))
            }
        case .failed(let id, let error):
            let message = error is CancellationError ? "Cancelled" : FriendlyError.message(for: error)
            update(id) { $0.state = error is CancellationError ? .waiting : .failed(message) }
        }
    }

    private func update(_ id: UUID, _ change: (inout Item) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(Tokens.Motion.snappy) { change(&items[index]) }
    }

    // MARK: - Saving

    func saveAll() async -> Bool {
        let files = outputFiles
        guard !files.isEmpty,
              await PHPhotoLibrary.requestAuthorization(for: .addOnly) == .authorized
        else { return false }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                for url in files {
                    PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: url, options: nil)
                }
            }
            savedCount = files.count
            return true
        } catch {
            return false
        }
    }
}
