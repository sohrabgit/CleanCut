import CoreImage
import CoreImage.CIFilterBuiltins

/// What the pipeline needs to know about one photo.
public struct PipelineInputs: Sendable {
    /// The upright photo, extent starting at (0, 0).
    public let source: CIImage
    /// Subject coverage in the red channel (`0...1`), same extent as `source`,
    /// not color-managed.
    public let mask: CIImage
    /// The subject's bounding box in `source` pixel coordinates (bottom-left origin).
    public let subjectBounds: CGRect

    public init(source: CIImage, mask: CIImage, subjectBounds: CGRect) {
        self.source = source
        self.mask = mask
        self.subjectBounds = subjectBounds
    }
}

/// The image pipeline: `(inputs, recipe, output size) -> CIImage`.
///
/// Pure and lazy — it only describes a Core Image graph; nothing is rendered until
/// a `CIContext` draws the result. The live preview and the export call this same
/// function; only `outputSize` differs.
public enum Pipeline {
    public static func makeImage(
        _ inputs: PipelineInputs,
        recipe: Recipe,
        outputSize: CGSize,
        kernels: EdgeKernels? = .shared
    ) -> CIImage {
        let recipe = recipe.clamped()
        let outputRect = CGRect(origin: .zero, size: outputSize)

        // 1. Framing. Map source and mask into output space first, so every later
        //    stage (blurs, kernel, compositing) runs at output resolution.
        let canvas = Framing.canvasRect(
            subject: inputs.subjectBounds,
            aspectRatio: outputSize.width / outputSize.height,
            fill: recipe.preset.fill
        )
        let toOutput = Framing.transform(from: canvas, to: outputSize)
        let subject = inputs.subjectBounds.applying(toOutput)
        // The unit all relative recipe lengths are measured in.
        let unit = max(min(subject.width, subject.height), 1)

        let source = inputs.source.resampled(by: toOutput).cropped(to: outputRect)
        var matte = Matte.canonical(inputs.mask.resampled(by: toOutput)).cropped(to: outputRect)

        // 2. Edge softening.
        let feather = recipe.edges.feather * unit
        if feather >= 0.3 {
            matte = matte.applyingGaussianBlur(sigma: feather).cropped(to: outputRect)
        }

        // 3. Edge decontamination (custom Metal kernel).
        var foreground = source
        if recipe.edges.cleanEdges, recipe.edges.cleanStrength > 0, let kernels {
            foreground = kernels.decontaminate(
                image: source,
                matte: matte,
                strength: recipe.edges.cleanStrength,
                backgroundRadius: max(4, 0.05 * unit)
            )
        }
        let cutout = foreground.applyingFilter("CIBlendWithRedMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(),
            kCIInputMaskImageKey: matte,
        ])
        // Background / shadow tweaks shouldn't re-run the kernel.
        .insertingIntermediate(cache: true)

        // 4. Shadows, built from the mask.
        let shadows = ShadowBuilder.makeShadows(matte: matte, subject: subject, unit: unit, style: recipe.shadow)

        // 5. Background.
        let background = BackgroundBuilder.makeBackground(recipe.effectiveBackground, in: outputRect)

        return cutout
            .composited(over: shadows.composited(over: background))
            .cropped(to: outputRect)
    }
}

/// Mask normalization.
enum Matte {
    /// Normalizes any mask to opaque gray `(v, v, v, 1)` with `v` taken from the
    /// red channel and clamped to `0...1`, defined over the infinite plane
    /// (zero outside the mask's extent) so blurs never pull in undefined pixels.
    static func canonical(_ mask: CIImage) -> CIImage {
        let red = CIVector(x: 1, y: 0, z: 0, w: 0)
        return mask
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": red,
                "inputGVector": red,
                "inputBVector": red,
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ])
            .applyingFilter("CIColorClamp")
            .composited(over: CIImage(color: .black))
    }

    /// Turns a canonical matte into a black image with the matte as alpha.
    static func shadowShape(_ matte: CIImage, opacity: Double) -> CIImage {
        let zero = CIVector(x: 0, y: 0, z: 0, w: 0)
        return matte.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": zero,
            "inputGVector": zero,
            "inputBVector": zero,
            "inputAVector": CIVector(x: opacity, y: 0, z: 0, w: 0),
            "inputBiasVector": zero,
        ])
    }
}

extension CIImage {
    /// Scales/translates an image and keeps it strictly inside its new extent.
    ///
    /// High-quality (Lanczos) resampling clamps at the image border, so without
    /// the crop a product touching the photo's edge would smear its edge pixels
    /// across the whole canvas. Lanczos is only worth it when shrinking.
    public func resampled(by transform: CGAffineTransform) -> CIImage {
        let scale = hypot(transform.a, transform.c)
        return transformed(by: transform, highQualityDownsample: scale < 1)
            .cropped(to: extent.applying(transform))
    }
}
