import CoreGraphics
import os

/// Tries a primary engine and, only when it can't run here
/// (`SegmentationError.unavailable`), falls back to another. Real failures like
/// "no product found" are reported, not papered over.
public final class FallbackSegmenter: Segmenter {
    public let primary: any Segmenter
    public let fallback: any Segmenter
    private let used = OSAllocatedUnfairLock(initialState: "")

    public init(primary: any Segmenter, fallback: any Segmenter) {
        self.primary = primary
        self.fallback = fallback
    }

    public var name: String { "\(primary.name) → \(fallback.name)" }

    /// The engine that handled the most recent call.
    public var lastUsedName: String { used.withLock { $0 } }

    public func segment(_ image: CGImage) async throws -> SegmentationResult {
        do {
            let result = try await primary.segment(image)
            used.withLock { $0 = primary.name }
            return result
        } catch SegmentationError.unavailable {
            let result = try await fallback.segment(image)
            used.withLock { $0 = fallback.name }
            return result
        }
    }
}
