import Foundation

/// Everything that describes *how* a product photo is edited — and nothing about
/// *which* photo. A recipe is a plain value: it can be diffed, undone, persisted,
/// and applied unchanged to a whole batch.
///
/// All lengths are relative (fractions of the subject's short side), so the same
/// recipe produces the same look on a 1000 px preview and a 4000 px export.
public struct Recipe: Codable, Hashable, Sendable {
    /// Vision instance indices to keep; `nil` keeps every detected instance.
    public var selectedInstances: Set<Int>?
    public var background: BackgroundStyle
    public var shadow: ShadowStyle
    public var edges: EdgeSettings
    public var presetID: ExportPreset.ID

    public init(
        selectedInstances: Set<Int>? = nil,
        background: BackgroundStyle = .solid(.white),
        shadow: ShadowStyle = .natural,
        edges: EdgeSettings = .default,
        presetID: ExportPreset.ID = .depop
    ) {
        self.selectedInstances = selectedInstances
        self.background = background
        self.shadow = shadow
        self.edges = edges
        self.presetID = presetID
    }

    public static let `default` = Recipe()

    public var preset: ExportPreset { ExportPreset.preset(for: presetID) }

    /// The background actually rendered: presets like Amazon force pure white.
    public var effectiveBackground: BackgroundStyle {
        preset.requiredBackground ?? background
    }

    /// Returns a copy with every parameter inside its supported range. The
    /// pipeline only ever renders clamped recipes, so decoded or hand-built values
    /// can't produce out-of-range filter inputs.
    public func clamped() -> Recipe {
        var copy = self
        copy.shadow = shadow.clamped()
        copy.edges = edges.clamped()
        return copy
    }
}

public enum BackgroundStyle: Codable, Hashable, Sendable {
    /// A flat color.
    case solid(RGBA)
    /// A soft top-to-bottom studio gradient built around the given color.
    case studioSweep(RGBA)
    /// No background; only exportable to formats with alpha.
    case transparent

    public var baseColor: RGBA? {
        switch self {
        case .solid(let color), .studioSweep(let color): color
        case .transparent: nil
        }
    }
}

public struct ShadowStyle: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        /// No shadow.
        case none
        /// A soft, offset drop shadow — the product floats slightly.
        case soft
        /// A tight, dark shadow where the product touches the floor.
        case contact
        /// Contact + soft together: grounded and three-dimensional.
        case natural

        public var hasDrop: Bool { self == .soft || self == .natural }
        public var hasContact: Bool { self == .contact || self == .natural }
    }

    public var kind: Kind
    /// Overall shadow strength, `0...1`.
    public var intensity: Double
    /// Direction the drop shadow falls, in degrees; 270 is straight down.
    public var angle: Double
    /// Drop shadow offset as a fraction of the subject's short side, `0...0.3`.
    public var distance: Double
    /// Drop shadow blur as a fraction of the subject's short side, `0.005...0.3`.
    public var softness: Double

    public init(kind: Kind, intensity: Double = 0.6, angle: Double = 270, distance: Double = 0.04, softness: Double = 0.06) {
        self.kind = kind
        self.intensity = intensity
        self.angle = angle
        self.distance = distance
        self.softness = softness
    }

    public static let none = ShadowStyle(kind: .none)
    public static let soft = ShadowStyle(kind: .soft)
    public static let contact = ShadowStyle(kind: .contact)
    public static let natural = ShadowStyle(kind: .natural)

    public static let intensityRange: ClosedRange<Double> = 0...1
    public static let distanceRange: ClosedRange<Double> = 0...0.3
    public static let softnessRange: ClosedRange<Double> = 0.005...0.3

    public func clamped() -> ShadowStyle {
        var copy = self
        copy.intensity = intensity.clamped(to: Self.intensityRange)
        copy.distance = distance.clamped(to: Self.distanceRange)
        copy.softness = softness.clamped(to: Self.softnessRange)
        let wrapped = angle.truncatingRemainder(dividingBy: 360)
        copy.angle = wrapped < 0 ? wrapped + 360 : wrapped
        return copy
    }
}

public struct EdgeSettings: Codable, Hashable, Sendable {
    /// Edge softening as a fraction of the subject's short side, `0...0.02`.
    public var feather: Double
    /// Removes background color bleeding into the subject's edges.
    public var cleanEdges: Bool
    /// How much of the estimated background contamination to remove, `0...1`.
    public var cleanStrength: Double

    public init(feather: Double = 0.002, cleanEdges: Bool = true, cleanStrength: Double = 0.85) {
        self.feather = feather
        self.cleanEdges = cleanEdges
        self.cleanStrength = cleanStrength
    }

    public static let `default` = EdgeSettings()

    public static let featherRange: ClosedRange<Double> = 0...0.02
    public static let strengthRange: ClosedRange<Double> = 0...1

    public func clamped() -> EdgeSettings {
        var copy = self
        copy.feather = feather.clamped(to: Self.featherRange)
        copy.cleanStrength = cleanStrength.clamped(to: Self.strengthRange)
        return copy
    }
}
