import CoreGraphics

/// Pure geometry for auto-cropping around the subject.
public enum Framing {
    /// The canvas rectangle, in source coordinates, that frames `subject` for an
    /// output with the given aspect ratio (width / height).
    ///
    /// The canvas is the smallest rectangle of that aspect ratio in which the
    /// subject spans at most `fill` of the width and at most `fill` of the
    /// height, centered on the subject. It may extend past the source image; the
    /// pipeline paints a background there.
    public static func canvasRect(subject: CGRect, aspectRatio: Double, fill: Double) -> CGRect {
        precondition(aspectRatio > 0, "aspect ratio must be positive")
        let fill = fill.clamped(to: 0.05...1)
        let subject = subject.standardized
        // Guard against empty masks: frame at least a 1×1 point.
        let width = max(subject.width, 1)
        let height = max(subject.height, 1)

        let canvasWidth = max(width / fill, height * aspectRatio / fill)
        let canvasHeight = canvasWidth / aspectRatio
        return CGRect(
            x: subject.midX - canvasWidth / 2,
            y: subject.midY - canvasHeight / 2,
            width: canvasWidth,
            height: canvasHeight
        )
    }

    /// Maps the canvas rectangle onto an output of `outputSize` pixels whose
    /// origin is (0, 0).
    public static func transform(from canvas: CGRect, to outputSize: CGSize) -> CGAffineTransform {
        let scale = outputSize.width / canvas.width
        return CGAffineTransform(translationX: -canvas.minX, y: -canvas.minY)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
    }
}

/// Pure geometry for placing images inside views.
public enum ViewportMath {
    /// The largest rect with `contentSize`'s aspect ratio centered inside `bounds`.
    public static func aspectFit(_ contentSize: CGSize, in bounds: CGRect) -> CGRect {
        guard contentSize.width > 0, contentSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            return CGRect(origin: CGPoint(x: bounds.midX, y: bounds.midY), size: .zero)
        }
        let scale = min(bounds.width / contentSize.width, bounds.height / contentSize.height)
        let size = CGSize(width: contentSize.width * scale, height: contentSize.height * scale)
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    /// Converts a point in a view (top-left origin) to normalized image
    /// coordinates (top-left origin, `0...1`) for an image drawn at `imageRect`.
    /// Returns `nil` when the point falls outside the image.
    public static func normalizedPoint(_ point: CGPoint, inImageRect imageRect: CGRect) -> CGPoint? {
        guard imageRect.width > 0, imageRect.height > 0, imageRect.contains(point) else { return nil }
        return CGPoint(
            x: (point.x - imageRect.minX) / imageRect.width,
            y: (point.y - imageRect.minY) / imageRect.height
        )
    }
}
