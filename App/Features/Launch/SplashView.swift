import SwiftUI

/// Picks up exactly where the system launch screen (`UILaunchScreen` in
/// `App/Info.plist`) leaves off, twinkles the sparkles, then clears to reveal
/// Home. Without it the solid teal launch screen cuts hard to the light Home screen.
///
/// Home is built underneath from the first frame, so the splash only costs
/// the length of its animation (0.95 s, or 0.5 s with Reduce Motion).
struct SplashView: View {
    /// Called once the splash has fully faded, so the caller can remove it.
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isTwinkling = false
    @State private var isLeaving = false

    /// Must match the launch logo's point size (see `Tools/scripts/make-app-icon.swift`)
    /// so the first frame lines up with the launch screen pixel for pixel.
    fileprivate static let logoSize: CGFloat = 200

    var body: some View {
        ZStack {
            Color("LaunchBackground")
            ZStack(alignment: .topLeading) {
                Image("LaunchProduct")
                    .resizable()
                ForEach(Sparkle.all) { sparkle in
                    SparkleShape()
                        .fill(.white.opacity(sparkle.opacity))
                        .frame(width: sparkle.diameter, height: sparkle.diameter)
                        .keyframeAnimator(initialValue: Twinkle(), trigger: isTwinkling) { content, twinkle in
                            content
                                .scaleEffect(twinkle.scale)
                                .rotationEffect(.degrees(twinkle.angle))
                        } keyframes: { _ in
                            // Hold for the stagger, then a quarter turn with a
                            // swell: the four-point star ends where it started.
                            // Every delay must be above zero: a zero-length
                            // keyframe makes the value NaN and hides the sparkle.
                            KeyframeTrack(\.scale) {
                                LinearKeyframe(1, duration: sparkle.delay)
                                CubicKeyframe(1.35, duration: 0.2)
                                SpringKeyframe(1, duration: 0.3)
                            }
                            KeyframeTrack(\.angle) {
                                LinearKeyframe(0, duration: sparkle.delay)
                                CubicKeyframe(90, duration: 0.45)
                            }
                        }
                        .position(sparkle.center)
                }
            }
            .frame(width: Self.logoSize, height: Self.logoSize)
            // With Reduce Motion nothing moves and the splash only fades;
            // otherwise the logo lifts toward the viewer as the backdrop clears.
            .scaleEffect(isLeaving && !reduceMotion ? 1.15 : 1)
        }
        .ignoresSafeArea()
        .opacity(isLeaving ? 0 : 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            if !reduceMotion {
                isTwinkling = true
                try? await Task.sleep(for: .milliseconds(450))
            }
            withAnimation(.easeIn(duration: 0.35).delay(0.15)) {
                isLeaving = true
            } completion: {
                onFinished()
            }
        }
    }
}

private struct Twinkle {
    var scale: CGFloat = 1
    var angle: Double = 0
}

/// A sparkle from the app icon, placed in the 200-pt launch logo.
private struct Sparkle: Identifiable {
    let id: Int
    let center: CGPoint
    let diameter: CGFloat
    let opacity: Double
    let delay: Double

    /// The icon script draws these in a 1024-pt, y-up space and crops the
    /// launch logo to x 108–868, y 150–910 of it.
    init(id: Int, iconCenter: CGPoint, iconRadius: CGFloat, opacity: Double, delay: Double) {
        let scale = SplashView.logoSize / 760
        self.id = id
        self.center = CGPoint(x: (iconCenter.x - 108) * scale, y: (910 - iconCenter.y) * scale)
        self.diameter = iconRadius * 2 * scale
        self.opacity = opacity
        self.delay = delay
    }

    static let all = [
        Sparkle(id: 0, iconCenter: CGPoint(x: 742, y: 790), iconRadius: 70, opacity: 1, delay: 0.05),
        Sparkle(id: 1, iconCenter: CGPoint(x: 820, y: 680), iconRadius: 32, opacity: 0.75, delay: 0.17),
    ]
}

/// The icon's four-point sparkle: quad curves pinched toward the centre.
private struct SparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let waist = r * 0.18
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - r))
        p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + waist, y: c.y - waist))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x + waist, y: c.y + waist))
        p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - waist, y: c.y + waist))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x - waist, y: c.y - waist))
        p.closeSubpath()
        return p
    }
}
