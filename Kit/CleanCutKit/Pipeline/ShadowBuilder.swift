import CoreImage

/// Builds shadows from the subject's matte. All sizes scale with `unit` (the
/// subject's short side in output pixels), so shadows look the same at any size.
enum ShadowBuilder {
    static func makeShadows(matte: CIImage, subject: CGRect, unit: CGFloat, style: ShadowSettings) -> CIImage {
        var layers: [CIImage] = []
        if style.kind.hasDrop {
            layers.append(dropShadow(matte: matte, unit: unit, style: style))
        }
        if style.kind.hasContact {
            layers.append(contentsOf: contactShadow(matte: matte, subject: subject, unit: unit, intensity: style.intensity))
        }
        return layers.reduce(CIImage.empty()) { $1.composited(over: $0) }
    }

    /// The silhouette, offset along the light direction and blurred: the product
    /// floats slightly above the backdrop.
    private static func dropShadow(matte: CIImage, unit: CGFloat, style: ShadowSettings) -> CIImage {
        let radians = style.angle * .pi / 180
        let distance = style.distance * unit
        let offset = CGAffineTransform(translationX: cos(radians) * distance, y: sin(radians) * distance)
        return Matte.shadowShape(matte, opacity: 0.45 * style.intensity)
            .transformed(by: offset)
            .applyingGaussianBlur(sigma: style.softness * unit)
    }

    /// Where the product touches the floor: the bottom slice of the silhouette,
    /// flattened onto the floor plane. A tight dark core plus a wider ambient
    /// occlusion falloff read as "resting on a surface".
    private static func contactShadow(matte: CIImage, subject: CGRect, unit: CGFloat, intensity: Double) -> [CIImage] {
        // The footprint: bottom 12% of the subject.
        let footprint = CGRect(
            x: subject.minX - unit,
            y: subject.minY,
            width: subject.width + 2 * unit,
            height: max(subject.height * 0.12, 1)
        )
        // Flatten about the base line and widen slightly so it peeks out the sides.
        let flatten = CGAffineTransform(translationX: subject.midX, y: subject.minY)
            .scaledBy(x: 1.06, y: 0.22)
            .translatedBy(x: -subject.midX, y: -subject.minY)
            .concatenating(CGAffineTransform(translationX: 0, y: -0.006 * unit))

        let base = matte.cropped(to: footprint).transformed(by: flatten)
        let core = Matte.shadowShape(base, opacity: 0.75 * intensity)
            .applyingGaussianBlur(sigma: max(0.8, 0.01 * unit))
        let ambient = Matte.shadowShape(base, opacity: 0.35 * intensity)
            .applyingGaussianBlur(sigma: max(2, 0.05 * unit))
        return [ambient, core]
    }
}

/// Builds the backdrop behind the subject.
enum BackgroundBuilder {
    static func makeBackground(_ style: Backdrop, in rect: CGRect) -> CIImage {
        switch style {
        case .transparent:
            return CIImage.empty()
        case .solid(let color):
            return CIImage(color: color.ciColor).cropped(to: rect)
        case .studioSweep(let color):
            return studioSweep(color, in: rect)
        }
    }

    /// A photographer's paper sweep: lighter at the top, slightly darker at the
    /// floor, with a soft vignette that keeps the eye on the product.
    private static func studioSweep(_ color: RGBA, in rect: CGRect) -> CIImage {
        let gradient = CIFilter(name: "CISmoothLinearGradient", parameters: [
            "inputPoint0": CIVector(x: rect.midX, y: rect.maxY),
            "inputPoint1": CIVector(x: rect.midX, y: rect.minY),
            "inputColor0": color.adjustingBrightness(0.10).ciColor,
            "inputColor1": color.adjustingBrightness(-0.10).ciColor,
        ])!.outputImage!

        let radius = max(rect.width, rect.height)
        let vignette = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": CIVector(x: rect.midX, y: rect.minY + rect.height * 0.55),
            "inputRadius0": radius * 0.25,
            "inputRadius1": radius * 0.85,
            "inputColor0": CIColor(red: 0, green: 0, blue: 0, alpha: 0),
            "inputColor1": CIColor(red: 0, green: 0, blue: 0, alpha: 0.10),
        ])!.outputImage!

        return vignette.composited(over: gradient).cropped(to: rect)
    }
}
