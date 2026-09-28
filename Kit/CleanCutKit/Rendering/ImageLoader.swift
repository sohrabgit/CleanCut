import CoreGraphics
import Foundation
import ImageIO

/// Decodes photos with ImageIO, downsampling during decode.
///
/// Decoding straight to the size we need (instead of decoding 48 MP and then
/// scaling) is the single biggest memory win for photo apps: a 48 MP HEIC never
/// becomes a 190 MB bitmap.
public enum ImageLoader {
    /// Longest side of the "working" image. Exports top out at 2048 px and the
    /// subject is usually a fraction of the frame, so 4096 keeps full export
    /// quality while bounding memory.
    public static let workingMaxPixelSize = 4096

    public enum LoadError: Error, Sendable {
        case unreadable
    }

    public static func load(data: Data, maxPixelSize: Int = workingMaxPixelSize) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            throw LoadError.unreadable
        }
        return try decode(source, maxPixelSize: maxPixelSize)
    }

    public static func load(url: URL, maxPixelSize: Int = workingMaxPixelSize) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            throw LoadError.unreadable
        }
        return try decode(source, maxPixelSize: maxPixelSize)
    }

    private static var sourceOptions: CFDictionary {
        [kCGImageSourceShouldCache: false] as CFDictionary
    }

    private static func decode(_ source: CGImageSource, maxPixelSize: Int) throws -> CGImage {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // Bakes EXIF orientation into the pixels, so everything downstream is `.up`.
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw LoadError.unreadable
        }
        return image
    }
}
