import CoreImage
import Metal

/// Times live-preview frames the way the editor renders them: proxy inputs, a
/// shared GPU context, rendering into a Metal texture the size of a drawable.
/// Each scenario changes one recipe parameter per frame, like a slider drag.
///
/// Shared by `cleancut-bench preview` and the app's Benchmarks screen, so the
/// Mac and iPhone tables measure the same thing.
public struct PreviewBenchmark: Sendable {
    public struct Scenario: Sendable {
        public let name: String
        /// Sets the recipe for frame `index`.
        public let mutate: @Sendable (inout Recipe, Int) -> Void
    }

    public struct Row: Sendable, Codable, Equatable {
        public var scenario: String
        /// GPU execution time of the frame's command buffer.
        public var gpuP50MS: Double
        public var gpuP90MS: Double
        /// Building the image, encoding and waiting for the GPU: what a frame
        /// costs the app.
        public var frameP50MS: Double
        public var frameP90MS: Double
    }

    public static let scenarios: [Scenario] = [
        Scenario(name: "Redraw, nothing changed") { _, _ in },
        Scenario(name: "Drag shadow intensity") { recipe, i in recipe.shadow.intensity = 0.2 + 0.6 * Double(i % 60) / 60 },
        Scenario(name: "Drag edge-clean strength (re-runs kernel)") { recipe, i in recipe.edges.cleanStrength = 0.2 + 0.8 * Double(i % 60) / 60 },
        Scenario(name: "Switch backgrounds") { recipe, i in
            recipe.background = i.isMultiple(of: 2) ? .solid(.white) : .studioSweep(RGBA(hex: 0xEDEBE8))
        },
        // Worst case: a new matte invalidates the kernel, cutout and shadows.
        Scenario(name: "Drag edge softness (recomputes everything)") { recipe, i in recipe.edges.feather = 0.001 + 0.015 * Double(i % 60) / 60 },
    ]

    public let inputs: PipelineInputs
    public let size: CGSize
    public let frames: Int
    public let warmupFrames: Int

    public init(inputs: PipelineInputs, size: CGSize, frames: Int = 120, warmupFrames: Int = 10) {
        self.inputs = inputs
        self.size = size
        self.frames = frames
        self.warmupFrames = warmupFrames
    }

    public func run(_ scenario: Scenario, renderer: RenderService) async throws -> Row {
        guard let device = renderer.device, let queue = renderer.commandQueue else {
            throw BenchmarkError.needsMetal
        }
        let width = Int(size.width), height = Int(size.height)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderWrite, .shaderRead, .renderTarget]
        descriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw BenchmarkError.needsMetal }

        var recipe = Recipe.default
        var gpu: [Double] = [], total: [Double] = []
        let clock = ContinuousClock()
        for i in 0..<(frames + warmupFrames) {
            scenario.mutate(&recipe, i)
            let start = clock.now
            guard let buffer = queue.makeCommandBuffer() else { throw BenchmarkError.needsMetal }
            let destination = CIRenderDestination(width: width, height: height, pixelFormat: .bgra8Unorm, commandBuffer: buffer) { texture }
            destination.colorSpace = ColorSpaces.sRGB
            let frame = Pipeline.makeImage(inputs, recipe: recipe, outputSize: size)
            _ = try renderer.context.startTask(toRender: frame, to: destination)
            buffer.commit()
            await buffer.completed()
            guard i >= warmupFrames else { continue }
            gpu.append((buffer.gpuEndTime - buffer.gpuStartTime) * 1000)
            total.append((clock.now - start).milliseconds)
        }
        return Row(
            scenario: scenario.name,
            gpuP50MS: SegmentationBenchmark.percentile(gpu, 0.5), gpuP90MS: SegmentationBenchmark.percentile(gpu, 0.9),
            frameP50MS: SegmentationBenchmark.percentile(total, 0.5), frameP90MS: SegmentationBenchmark.percentile(total, 0.9)
        )
    }

    public static func markdown(_ rows: [Row]) -> String {
        var lines = ["| Scenario | GPU p50 | GPU p90 | Frame p50 (CPU+GPU) | Frame p90 |", "|---|---|---|---|---|"]
        for row in rows {
            lines.append(String(format: "| %@ | %.2f ms | %.2f ms | %.2f ms | %.2f ms |",
                                row.scenario, row.gpuP50MS, row.gpuP90MS, row.frameP50MS, row.frameP90MS))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

public enum BenchmarkError: Error, CustomStringConvertible {
    case needsMetal
    case noPhotos

    public var description: String {
        switch self {
        case .needsMetal: "This benchmark needs a Metal GPU."
        case .noPhotos: "No photo with a detectable product."
        }
    }
}
