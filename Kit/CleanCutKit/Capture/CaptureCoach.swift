/// What the capture screen shows: one tip, a state per check, and whether the
/// shot is ready.
public struct CaptureGuidance: Sendable, Equatable {
    /// Stable issues per check. A check that is absent passes, unless it hasn't
    /// been measured yet (see `passes(_:)`).
    public let issues: [CaptureCheck: CaptureIssue]
    let measured: Set<CaptureCheck>

    /// No frame analyzed yet.
    public static let pending = CaptureGuidance(issues: [:], measured: [])

    /// The one thing to fix first, by `CaptureCheck` order.
    public var tip: CaptureIssue? {
        issues.min { $0.key < $1.key }?.value
    }

    /// `nil` until the check has been measured.
    public func passes(_ check: CaptureCheck) -> Bool? {
        measured.contains(check) ? issues[check] == nil : nil
    }

    /// Every check measured and passing.
    public var isReady: Bool {
        measured.count == CaptureCheck.allCases.count && issues.isEmpty
    }
}

/// Turns per-frame assessments into steady advice.
///
/// Per-frame verdicts flicker (a hand shakes, auto-exposure hunts), and a tip
/// that changes every few frames is noise. A check only changes state after
/// the new state has held for `holdTime`. The first measurement of each check
/// is adopted immediately so the screen isn't blank at launch.
public struct CaptureCoach: Sendable {
    public var holdTime: Duration

    private var stable: [CaptureCheck: CaptureIssue?] = [:]
    private var pending: [CaptureCheck: (issue: CaptureIssue?, since: ContinuousClock.Instant)] = [:]

    public init(holdTime: Duration = .milliseconds(400)) {
        self.holdTime = holdTime
    }

    public mutating func update(_ assessment: CaptureAssessment, at now: ContinuousClock.Instant) -> CaptureGuidance {
        for check in CaptureCheck.allCases {
            let issue = assessment.issues[check]
            guard let current = stable[check] else {
                stable[check] = .some(issue)
                continue
            }
            if issue == current {
                pending[check] = nil
            } else if let candidate = pending[check], candidate.issue == issue {
                if now - candidate.since >= holdTime {
                    stable[check] = .some(issue)
                    pending[check] = nil
                }
            } else {
                pending[check] = (issue, now)
            }
        }
        return guidance
    }

    public var guidance: CaptureGuidance {
        CaptureGuidance(
            issues: stable.compactMapValues { $0 },
            measured: Set(stable.keys)
        )
    }
}
