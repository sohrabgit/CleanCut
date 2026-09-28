import SwiftUI

/// Design tokens. The UI is deliberately monochrome (system backgrounds and
/// materials) with a single accent color, so the product photo stays the hero.
enum Tokens {
    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let s: CGFloat = 12
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    enum Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 20
        static let card: CGFloat = 28
    }

    enum Size {
        /// Minimum hit target (Apple HIG).
        static let hitTarget: CGFloat = 44
        static let swatch: CGFloat = 40
        static let toolTrayHeight: CGFloat = 132
    }

    enum Motion {
        static let snappy = Animation.snappy(duration: 0.25)
        static let spring = Animation.spring(response: 0.45, dampingFraction: 0.82)
        static let lift = Animation.spring(response: 0.6, dampingFraction: 0.75)
    }
}

extension Color {
    /// Neutral surface behind the editing canvas (light gray / near black).
    static let canvasBackground = Color("CanvasBackground")
}

extension ShapeStyle where Self == Color {
    static var accent: Color { .accentColor }
}
