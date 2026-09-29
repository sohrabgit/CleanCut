import CoreGraphics
import CoreImage
import Foundation

/// One photo to process. `load` decodes it at no more than the given pixel
/// size, so a job holds no image memory until it actually runs.
public struct BatchJob: Sendable, Identifiable {
    public let id: UUID
    public let load: @Sendable (_ maxPixelSize: Int) async throws -> CGImage

    public init(id: UUID = UUID(), load: @escaping @Sendable (_ maxPixelSize: Int) async throws -> CGImage) {
        self.id = id
        self.load = load
    }
}

public struct BatchOutput: Sendable {
    public let jobID: UUID
    public let files: [ExportPreset.ID: URL]
    /// A small preview of the first preset, for progress grids.
    public let thumbnail: CGImage?
    public let duration: Duration
}

public enum BatchEvent: Sendable {
    case started(UUID)
    case finished(BatchOutput)
    case failed(UUID, any Error)
}

/// Processes many photos with one recipe, with bounded concurrency and
/// bounded memory.
///
/// Memory stays flat regardless of batch size because
/// - at most `maxConcurrentJobs` photos are in flight (a sliding window over a
///   task group, not one task per photo),
/// - each photo is decoded straight to `maxPixelSize` by ImageIO,
/// - nothing is kept after a job finishes except file URLs and a thumbnail,
/// - every photo renders through its own short-lived `CIContext`.
///
/// That last point is measured, not folklore: a long-lived Metal-backed context
/// grew to ~1.5 GB over a dozen differently sized 12 MP photos, and neither
/// `clearCaches()`, `cacheIntermediates: false` nor `.memoryTarget` released
/// it. A context per photo stays flat (see docs/DECISIONS.md, 006).
public struct BatchProcessor: Sendable {
    public let segmenter: any Segmenter
    /// Creates the render context for one photo.
    public let makeRenderer: @Sendable () -> RenderService
    public let maxConcurrentJobs: Int
    /// Longest side photos are decoded to. Exports top out at 2048 px, so 3072
    /// leaves headroom for the subject being a fraction of the frame.
    public let maxPixelSize: Int

    public init(
        segmenter: any Segmenter,
        makeRenderer: @escaping @Sendable () -> RenderService = { RenderService(cacheIntermediates: false) },
        maxConcurrentJobs: Int = 2,
        maxPixelSize: Int = 3072
    ) {
        precondition(maxConcurrentJobs > 0, "need at least one worker")
        self.segmenter = segmenter
        self.makeRenderer = makeRenderer
        self.maxConcurrentJobs = maxConcurrentJobs
        self.maxPixelSize = maxPixelSize
    }

    /// Streams progress events. Cancelling the consuming task (or dropping the
    /// stream) cancels in-flight work and starts no new jobs.
    public func process(
        _ jobs: [BatchJob],
        recipe: Recipe,
        presets: [ExportPreset],
        outputDirectory: URL
    ) -> AsyncStream<BatchEvent> {
        AsyncStream { continuation in
            let work = Task {
                await withTaskGroup(of: BatchEvent.self) { group in
                    var pending = jobs.makeIterator()
                    var inFlight = 0

                    // Prime the window, then start one new job per finished job.
                    while inFlight < maxConcurrentJobs, let job = pending.next() {
                        continuation.yield(.started(job.id))
                        group.addTask { await run(job, recipe: recipe, presets: presets, outputDirectory: outputDirectory) }
                        inFlight += 1
                    }
                    for await event in group {
                        continuation.yield(event)
                        guard !Task.isCancelled, let job = pending.next() else { continue }
                        continuation.yield(.started(job.id))
                        group.addTask { await run(job, recipe: recipe, presets: presets, outputDirectory: outputDirectory) }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in work.cancel() }
        }
    }

    private func run(_ job: BatchJob, recipe: Recipe, presets: [ExportPreset], outputDirectory: URL) async -> BatchEvent {
        let clock = ContinuousClock()
        let start = clock.now
        do {
            try Task.checkCancellation()
            let image = try await job.load(maxPixelSize)
            try Task.checkCancellation()
            let segmentation = try await segmenter.segment(image)
            try Task.checkCancellation()

            guard let bounds = segmentation.subjectBounds(for: nil) else { throw SegmentationError.noSubject }
            let inputs = PipelineInputs(
                source: CIImage(cgImage: image),
                mask: try segmentation.mask(for: nil),
                subjectBounds: bounds
            )
            let renderer = makeRenderer()
            // Batch applies the style but keeps every detected object.
            var recipe = recipe
            recipe.selectedInstances = nil

            var files: [ExportPreset.ID: URL] = [:]
            for preset in presets {
                try Task.checkCancellation()
                let data = try autoreleasepool {
                    try Exporter.export(inputs, recipe: recipe, preset: preset, renderer: renderer)
                }
                let url = outputDirectory.appendingPathComponent(
                    Exporter.fileName(for: preset, tag: String(job.id.uuidString.prefix(8)))
                )
                try data.write(to: url, options: .atomic)
                files[preset.id] = url
            }

            var thumbnailRecipe = recipe
            thumbnailRecipe.presetID = presets.first?.id ?? recipe.presetID
            let thumbnailSize = CGSize(width: 240, height: 240 / thumbnailRecipe.preset.aspectRatio)
            let thumbnail = autoreleasepool {
                renderer.makeCGImage(Pipeline.makeImage(inputs, recipe: thumbnailRecipe, outputSize: thumbnailSize))
            }
            return .finished(BatchOutput(jobID: job.id, files: files, thumbnail: thumbnail, duration: clock.now - start))
        } catch {
            return .failed(job.id, error)
        }
    }
}
