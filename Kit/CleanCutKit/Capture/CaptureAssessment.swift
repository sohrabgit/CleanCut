import CoreGraphics

/// The four things guided capture checks, in the order the coach raises them:
/// there's no point asking for light while the product is out of frame.
public enum CaptureCheck: Int, CaseIterable, Sendable, Comparable {
    case framing
    case light
    case sharpness
    case glare

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// A reason a frame would make a poor source photo. The app owns the wording.
public enum CaptureIssue: Sendable, Hashable, CaseIterable {
    /// Nothing that looks like a product.
    case noSubject
    /// The product runs off the frame, so its cutout would have a hard, false edge.
    case cutOff
    /// The product is small in the frame, so the export would be upscaled.
    case tooFar
    case tooDark
    case tooBright
    case blurry
    /// Specular hotspots: blown-out reflections with no detail to recover.
    case glare

    public var check: CaptureCheck {
        switch self {
        case .noSubject, .cutOff, .tooFar: .framing
        case .tooDark, .tooBright: .light
        case .blurry: .sharpness
        case .glare: .glare
        }
    }
}

/// Where each check flips. Heuristics, calibrated on synthetic scenes
/// (`ReplayScene`, `FrameAnalyzerTests`); see docs/DECISIONS.md, 010.
public struct CaptureThresholds: Sendable, Equatable {
    /// Below this `FrameMetrics.sharpness` the subject reads as blurry. Sharp
    /// test scenes score 0.4–3.5; a 2-px blur at analysis size drops them to
    /// 0.02–0.14, and handheld motion blur to ~0.001.
    public var minSharpness = 0.1
    /// Below this frame luma the scene is too dim (camera-encoded; mid-gray ≈ 0.46).
    public var minFrameLuma = 0.2
    /// Above this share of crushed subject pixels, the product is too dark.
    public var maxShadowClip = 0.35
    /// Above this share of blown subject pixels, the product is overexposed.
    public var maxHighlightClip = 0.2
    /// At or above this share of specular subject pixels, there is glare.
    public var minSpecular = 0.004
    /// Below this frame coverage, the "subject" is noise.
    public var minSubjectCoverage = 0.01
    /// Within this normalized distance of the frame's edge, the subject is cut off.
    public var edgeMargin = 0.01
    /// The subject's larger side must span at least this share of the frame.
    public var minSubjectSpan = 0.4

    public init() {}

    public static let `default` = CaptureThresholds()
}

/// One frame's verdict: at most one issue per check.
public struct CaptureAssessment: Sendable, Equatable {
    public let issues: [CaptureCheck: CaptureIssue]

    public init(issues: [CaptureCheck: CaptureIssue]) {
        self.issues = issues
    }

    public init(_ metrics: FrameMetrics, thresholds: CaptureThresholds = .default) {
        var issues: [CaptureCheck: CaptureIssue] = [:]
        issues[.framing] = Self.framing(metrics, thresholds)

        if metrics.frameLuma < thresholds.minFrameLuma || metrics.shadowClip > thresholds.maxShadowClip {
            issues[.light] = .tooDark
        } else if metrics.highlightClip > thresholds.maxHighlightClip {
            issues[.light] = .tooBright
        }

        if metrics.sharpness < thresholds.minSharpness {
            issues[.sharpness] = .blurry
        }

        // An overexposed product is a light problem, not glare.
        if metrics.specular >= thresholds.minSpecular, issues[.light] != .tooBright {
            issues[.glare] = .glare
        }
        self.issues = issues
    }

    private static func framing(_ metrics: FrameMetrics, _ thresholds: CaptureThresholds) -> CaptureIssue? {
        guard let bounds = metrics.subjectBounds, metrics.subjectCoverage >= thresholds.minSubjectCoverage else {
            return .noSubject
        }
        let margin = thresholds.edgeMargin
        if bounds.minX <= margin || bounds.minY <= margin || bounds.maxX >= 1 - margin || bounds.maxY >= 1 - margin {
            return .cutOff
        }
        // No centering check: the editor reframes the product anyway. Only
        // "all of it" and "enough pixels" survive into the export.
        if max(bounds.width, bounds.height) < thresholds.minSubjectSpan {
            return .tooFar
        }
        return nil
    }
}
