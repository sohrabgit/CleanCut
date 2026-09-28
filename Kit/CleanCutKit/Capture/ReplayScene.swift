import CoreImage
import CoreImage.CIFilterBuiltins

/// A capture situation the replay camera can stage, one per coaching tip.
public enum CaptureScenario: String, CaseIterable, Sendable {
    case good
    case tooFar
    case cutOff
    case dark
    case bright
    case blurry
    case glare

    /// The issue this scenario is built to trigger.
    public var expectedIssue: CaptureIssue? {
        switch self {
        case .good: nil
        case .tooFar: .tooFar
        case .cutOff: .cutOff
        case .dark: .tooDark
        case .bright: .tooBright
        case .blurry: .blurry
        case .glare: .glare
        }
    }
}

/// A generated product shot (a bottle on a tabletop) that stands in for the
/// camera where there is none: the Simulator, UI tests and the demo. Each
/// `CaptureScenario` degrades it the way a real capture goes wrong.
///
/// Drawn entirely with Core Image generators, so it needs no bundled photos
/// and is identical on every machine. Values are **camera-encoded**: render the
/// frames with a context that isn't color-managed, as `FrameAnalyzer` does.
public struct ReplayScene: Sendable {
    public let size: CGSize

    /// The demo loop: each problem in turn, then a good shot to take.
    public static let timeline: [(scenario: CaptureScenario, seconds: Double)] = [
        (.tooFar, 3), (.cutOff, 3), (.dark, 3), (.blurry, 3), (.glare, 3), (.good, 5),
    ]

    public init(size: CGSize = CGSize(width: 1080, height: 1440)) {
        self.size = size
    }

    public var extent: CGRect { CGRect(origin: .zero, size: size) }

    /// The scenario playing `time` seconds into the looping timeline.
    public static func scenario(at time: Double) -> CaptureScenario {
        let total = timeline.reduce(0) { $0 + $1.seconds }
        var t = time.truncatingRemainder(dividingBy: total)
        for step in timeline {
            if t < step.seconds { return step.scenario }
            t -= step.seconds
        }
        return .good
    }

    /// The bottle's bounding box (Core Image coordinates, bottom-left origin).
    /// `time` adds a slow handheld drift.
    public func productRect(for scenario: CaptureScenario, time: Double = 0) -> CGRect {
        let w = size.width, h = size.height
        var rect: CGRect
        switch scenario {
        case .tooFar:
            rect = CGRect(x: 0, y: 0, width: 0.14 * w, height: 0.26 * h).offsetBy(dx: 0.43 * w, dy: 0.3 * h)
        case .cutOff:
            // Too close: the cap leaves the top of the frame.
            rect = CGRect(x: 0, y: 0, width: 0.42 * w, height: 0.76 * h).offsetBy(dx: 0.29 * w, dy: 0.36 * h)
        default:
            rect = CGRect(x: 0, y: 0, width: 0.32 * w, height: 0.58 * h).offsetBy(dx: 0.34 * w, dy: 0.2 * h)
        }
        let drift = CGPoint(x: sin(time * 1.3) * 0.006 * w, y: cos(time * 1.7) * 0.005 * h)
        return rect.offsetBy(dx: drift.x, dy: drift.y)
    }

    /// One camera frame.
    public func frame(_ scenario: CaptureScenario, time: Double = 0) -> CIImage {
        let product = productRect(for: scenario, time: time)
        var image = bottle(in: product).composited(over: shadow(under: product)).composited(over: backdrop)

        switch scenario {
        case .dark: image = Self.exposure(image, ev: -4.5)
        case .bright: image = Self.exposure(image, ev: 2)
        case .blurry:
            image = image.clampedToExtent()
                .applyingFilter("CIMotionBlur", parameters: [kCIInputRadiusKey: 0.02 * min(size.width, size.height), kCIInputAngleKey: 0.35])
        case .glare:
            let spot = CGPoint(x: product.minX + 0.3 * product.width, y: product.minY + 0.52 * product.height)
            image = Self.hotspot(at: spot, radius: 0.08 * product.width).composited(over: image)
        case .good, .tooFar, .cutOff: break
        }
        // Sensor noise comes after the optics, so blur doesn't smooth it away.
        return noise.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: image])
            .cropped(to: extent)
    }

    /// Where the bottle is, as coverage in red: ground truth for tests.
    public func mask(_ scenario: CaptureScenario, time: Double = 0) -> CIImage {
        silhouette(in: productRect(for: scenario, time: time))
            .composited(over: CIImage(color: .black))
            .cropped(to: extent)
    }

    // MARK: - Drawing

    private var backdrop: CIImage {
        let horizon = 0.42 * size.height
        let wall = Self.verticalGradient(from: 0.80, at: horizon, to: 0.90, at: size.height, tint: RGBA(red: 1, green: 0.99, blue: 0.97))
            .cropped(to: CGRect(x: 0, y: horizon, width: size.width, height: size.height - horizon))
        let table = Self.verticalGradient(from: 0.62, at: 0, to: 0.72, at: horizon, tint: RGBA(red: 1, green: 0.9, blue: 0.78))
            .cropped(to: CGRect(x: 0, y: 0, width: size.width, height: horizon))
        return wall.composited(over: table)
    }

    private var noise: CIImage {
        // Zero-mean gray noise, ±1.2%.
        CIFilter.randomGenerator().outputImage!
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.024, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0.024, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 0.024, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: -0.012, y: -0.012, z: -0.012, w: 0),
            ])
            .cropped(to: extent)
    }

    /// Body, neck and cap as one white shape.
    private func silhouette(in r: CGRect) -> CIImage {
        let body = Self.roundedRect(CGRect(x: r.minX, y: r.minY, width: r.width, height: 0.7 * r.height), radius: 0.18 * r.width, color: .white)
        let neck = Self.roundedRect(CGRect(x: r.midX - 0.19 * r.width, y: r.minY + 0.6 * r.height, width: 0.38 * r.width, height: 0.3 * r.height), radius: 0.1 * r.width, color: .white)
        let cap = Self.roundedRect(CGRect(x: r.midX - 0.22 * r.width, y: r.minY + 0.86 * r.height, width: 0.44 * r.width, height: 0.14 * r.height), radius: 0.06 * r.width, color: .white)
        return cap.composited(over: neck).composited(over: body)
    }

    private func bottle(in r: CGRect) -> CIImage {
        let amber = CIImage(color: CIColor(red: 0.85, green: 0.52, blue: 0.22))
        // Cylinder shading: a soft highlight band and a darker right side.
        let highlight = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 0.35))
            .cropped(to: CGRect(x: r.minX + 0.24 * r.width, y: r.minY, width: 0.08 * r.width, height: r.height))
            .applyingGaussianBlur(sigma: 0.03 * r.width)
        let falloff = CIFilter.smoothLinearGradient()
        falloff.point0 = CGPoint(x: r.minX + 0.55 * r.width, y: 0)
        falloff.point1 = CGPoint(x: r.maxX, y: 0)
        falloff.color0 = CIColor(red: 0, green: 0, blue: 0, alpha: 0)
        falloff.color1 = CIColor(red: 0, green: 0, blue: 0, alpha: 0.35)

        // The label: a title band and a barcode, the fine detail a sharp photo keeps.
        let labelRect = CGRect(x: r.minX, y: r.minY + 0.2 * r.height, width: r.width, height: 0.26 * r.height)
        let label = CIImage(color: CIColor(red: 0.95, green: 0.93, blue: 0.88)).cropped(to: labelRect)
        let title = CIImage(color: CIColor(red: 0.2, green: 0.22, blue: 0.25))
            .cropped(to: CGRect(x: r.midX - 0.3 * r.width, y: labelRect.minY + 0.62 * labelRect.height, width: 0.6 * r.width, height: 0.14 * labelRect.height))
        let stripes = CIFilter.stripesGenerator()
        stripes.center = CGPoint(x: r.midX, y: 0)
        stripes.color0 = CIColor(red: 0.15, green: 0.15, blue: 0.15)
        stripes.color1 = CIColor(red: 0.95, green: 0.93, blue: 0.88)
        stripes.width = Float(max(2, 0.012 * r.width))
        let barcode = stripes.outputImage!
            .cropped(to: CGRect(x: r.midX - 0.18 * r.width, y: labelRect.minY + 0.15 * labelRect.height, width: 0.36 * r.width, height: 0.3 * labelRect.height))

        let cap = CIImage(color: CIColor(red: 0.16, green: 0.17, blue: 0.19))
            .cropped(to: CGRect(x: r.minX, y: r.minY + 0.86 * r.height, width: r.width, height: 0.14 * r.height))

        let paint = falloff.outputImage!
            .composited(over: highlight)
            .composited(over: cap)
            .composited(over: barcode)
            .composited(over: title)
            .composited(over: label)
            .composited(over: amber)
        return paint.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(),
            kCIInputMaskImageKey: silhouette(in: r),
        ])
    }

    /// A soft contact shadow under the base.
    private func shadow(under r: CGRect) -> CIImage {
        let gradient = CIFilter.radialGradient()
        gradient.center = .zero
        gradient.radius0 = 0
        gradient.radius1 = Float(0.62 * r.width)
        gradient.color0 = CIColor(red: 0, green: 0, blue: 0, alpha: 0.45)
        gradient.color1 = CIColor(red: 0, green: 0, blue: 0, alpha: 0)
        return gradient.outputImage!
            .transformed(by: CGAffineTransform(scaleX: 1, y: 0.16).concatenating(CGAffineTransform(translationX: r.midX, y: r.minY + 0.01 * r.height)))
            .cropped(to: extent)
    }

    // MARK: - Helpers

    private static func roundedRect(_ rect: CGRect, radius: CGFloat, color: CIColor) -> CIImage {
        let generator = CIFilter.roundedRectangleGenerator()
        generator.extent = rect
        generator.radius = Float(radius)
        generator.color = color
        return generator.outputImage!
    }

    private static func verticalGradient(from bottom: Double, at y0: CGFloat, to top: Double, at y1: CGFloat, tint: RGBA) -> CIImage {
        let gradient = CIFilter.smoothLinearGradient()
        gradient.point0 = CGPoint(x: 0, y: y0)
        gradient.point1 = CGPoint(x: 0, y: y1)
        gradient.color0 = CIColor(red: bottom * tint.red, green: bottom * tint.green, blue: bottom * tint.blue)
        gradient.color1 = CIColor(red: top * tint.red, green: top * tint.green, blue: top * tint.blue)
        return gradient.outputImage!
    }

    /// Exposure change in linear light, applied to encoded values.
    private static func exposure(_ image: CIImage, ev: Double) -> CIImage {
        let gain = pow(2, ev)
        return image
            .applyingFilter("CISRGBToneCurveToLinear")
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: gain, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: gain, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: gain, w: 0),
            ])
            .applyingFilter("CILinearToSRGBToneCurve")
            .applyingFilter("CIColorClamp")
    }

    /// A blown-out reflection: a white core fading out.
    private static func hotspot(at center: CGPoint, radius: CGFloat) -> CIImage {
        let gradient = CIFilter.radialGradient()
        gradient.center = center
        gradient.radius0 = Float(radius)
        gradient.radius1 = Float(radius * 2.2)
        gradient.color0 = CIColor(red: 1, green: 1, blue: 1, alpha: 1)
        gradient.color1 = CIColor(red: 1, green: 1, blue: 1, alpha: 0)
        return gradient.outputImage!.cropped(to: CGRect(x: center.x - radius * 2.2, y: center.y - radius * 2.2, width: radius * 4.4, height: radius * 4.4))
    }
}
