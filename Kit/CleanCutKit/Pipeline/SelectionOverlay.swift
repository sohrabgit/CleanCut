import CoreImage

/// Renders the "Select" view: the original photo, with the background and any
/// excluded objects dimmed, and every object outlined — selected ones in the
/// accent color, excluded ones in white.
public enum SelectionOverlay {
    public static func makeImage(
        photo: PreparedPhoto,
        selection: Set<Int>?,
        outputSize: CGSize,
        accent: RGBA,
        pulse: Double = 1
    ) -> CIImage {
        let source = photo.proxySource
        let outputRect = CGRect(origin: .zero, size: outputSize)
        let scale = min(outputSize.width / source.extent.width, outputSize.height / source.extent.height)
        let toOutput = CGAffineTransform(scaleX: scale, y: scale)
        let selected = photo.segmentation.resolvedSelection(selection)

        let photoImage = source.resampled(by: toOutput)
        let photoRect = photoImage.extent
        let selectedMatte = Matte.canonical(photo.proxyMask(for: selected).resampled(by: toOutput))
            .cropped(to: photoRect)

        // Dim everything that isn't selected.
        let dim = Matte.shadowShape(selectedMatte.applyingFilter("CIColorInvert"), opacity: 0.55)
        var image = dim.composited(over: photoImage)

        // Outline every object.
        let ringRadius = max(1.5, 0.004 * max(outputSize.width, outputSize.height))
        for instance in photo.instances {
            guard let mask = photo.proxyMasks[instance] else { continue }
            let isSelected = selected.contains(instance)
            let ring = Matte.canonical(mask.resampled(by: toOutput))
                .cropped(to: photoRect)
                .applyingFilter("CIMorphologyGradient", parameters: [kCIInputRadiusKey: ringRadius])
            let color = isSelected ? accent : RGBA.white
            let opacity = isSelected ? 0.55 + 0.45 * pulse : 0.7
            image = tinted(ring, color: color, opacity: opacity).composited(over: image)
        }
        return image.cropped(to: photoRect).cropped(to: outputRect)
    }

    /// The rect (in output pixels, bottom-left origin) where the photo lands.
    public static func photoSize(for photo: PreparedPhoto, in outputSize: CGSize) -> CGSize {
        let extent = photo.proxySource.extent
        let scale = min(outputSize.width / extent.width, outputSize.height / extent.height)
        return CGSize(width: extent.width * scale, height: extent.height * scale)
    }

    private static func tinted(_ matte: CIImage, color: RGBA, opacity: Double) -> CIImage {
        let zero = CIVector(x: 0, y: 0, z: 0, w: 0)
        return matte.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": zero,
            "inputGVector": zero,
            "inputBVector": zero,
            "inputAVector": CIVector(x: opacity, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: color.red, y: color.green, z: color.blue, w: 0),
        ])
    }
}
