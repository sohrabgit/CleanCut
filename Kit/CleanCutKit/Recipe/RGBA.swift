import CoreImage

/// An sRGB color with components in `0...1`.
///
/// Stored as plain doubles so recipes stay `Codable` and comparable; converted to
/// `CIColor` only at render time.
public struct RGBA: Codable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red.clamped(to: 0...1)
        self.green = green.clamped(to: 0...1)
        self.blue = blue.clamped(to: 0...1)
        self.alpha = alpha.clamped(to: 0...1)
    }

    /// Creates a color from a `0xRRGGBB` literal.
    public init(hex: UInt32, alpha: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    public static let white = RGBA(red: 1, green: 1, blue: 1)
    public static let black = RGBA(red: 0, green: 0, blue: 0)
    public static let clear = RGBA(red: 0, green: 0, blue: 0, alpha: 0)

    /// Mixes toward white (`amount > 0`) or black (`amount < 0`).
    public func adjustingBrightness(_ amount: Double) -> RGBA {
        let target = amount >= 0 ? 1.0 : 0.0
        let t = abs(amount).clamped(to: 0...1)
        return RGBA(
            red: red + (target - red) * t,
            green: green + (target - green) * t,
            blue: blue + (target - blue) * t,
            alpha: alpha
        )
    }

    public var ciColor: CIColor {
        CIColor(red: red, green: green, blue: blue, alpha: alpha, colorSpace: ColorSpaces.sRGB)!
    }
}

/// Color spaces used across the pipeline. Everything leaving CleanCut is sRGB.
public enum ColorSpaces {
    public static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    public static let linearSRGB = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
