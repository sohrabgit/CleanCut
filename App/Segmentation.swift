import CleanCutKit
import CoreML
import Foundation

/// The user-selectable segmentation engine (Settings).
enum SegmentationEngine: String, CaseIterable, Identifiable {
    /// Vision's foreground instance mask: multiple objects, tap to select.
    case vision
    /// U²-Netp via Core ML: one salient mask, split into separate objects; runs anywhere.
    case u2netp

    static let storageKey = "segmentationEngine"

    var id: Self { self }

    var title: String {
        switch self {
        case .vision: "Vision"
        case .u2netp: "U²-Netp (Core ML)"
        }
    }

    var detail: String {
        switch self {
        case .vision: "Apple's instance segmentation. Finds each object separately, so you can tap to choose."
        case .u2netp: "Open-source model (Apache-2.0) running on the Neural Engine. Separate products can still be tapped; touching ones stay together."
        }
    }

    static var current: SegmentationEngine {
        UserDefaults.standard.string(forKey: storageKey).flatMap(SegmentationEngine.init) ?? .vision
    }
}

enum Segmenters {
    /// The segmenter for the current setting. Vision falls back to U²-Netp where
    /// it can't run (the Simulator).
    static func make(renderer: RenderService, engine: SegmentationEngine = .current) -> any Segmenter {
        guard let u2netp = try? u2netp(renderer: renderer) else { return VisionSegmenter() }
        switch engine {
        case .vision: return FallbackSegmenter(primary: VisionSegmenter(), fallback: u2netp)
        case .u2netp: return u2netp
        }
    }

    /// Fastest configuration in docs/BENCHMARKS.md: CPU + Neural Engine.
    static func u2netp(renderer: RenderService) throws -> CoreMLSegmenter {
        guard let url = Bundle.main.url(forResource: "U2Netp", withExtension: "mlmodelc") else {
            throw SegmentationError.unavailable("U²-Netp model missing from the app bundle")
        }
        return try CoreMLSegmenter(compiledModelAt: url, name: "U²-Netp", computeUnits: .cpuAndNeuralEngine, renderer: renderer)
    }
}
