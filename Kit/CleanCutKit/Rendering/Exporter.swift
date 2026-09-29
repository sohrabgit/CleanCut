import CoreImage
import Foundation
import ImageIO

/// Full-quality export: renders a recipe from the working image and encodes it
/// for a marketplace preset.
public enum Exporter {
    public enum ExportError: Error, Sendable {
        case nothingSelected
        case encodingFailed
    }

    public static let jpegQuality = 0.92

    /// Renders and encodes one preset. Uses the working-resolution image and a
    /// freshly generated full-resolution mask, never the preview proxy.
    public static func export(
        _ photo: PreparedPhoto,
        recipe: Recipe,
        preset: ExportPreset,
        renderer: RenderService
    ) throws -> Data {
        guard let inputs = try photo.exportInputs(selection: recipe.selectedInstances) else {
            throw ExportError.nothingSelected
        }
        return try export(inputs, recipe: recipe, preset: preset, renderer: renderer)
    }

    public static func export(
        _ inputs: PipelineInputs,
        recipe: Recipe,
        preset: ExportPreset,
        renderer: RenderService
    ) throws -> Data {
        var recipe = recipe
        recipe.presetID = preset.id
        let image = Pipeline.makeImage(inputs, recipe: recipe, outputSize: preset.pixelSize)
        return try encode(image, as: preset.fileType, renderer: renderer)
    }

    /// Encodes as 8-bit sRGB. JPEG output is flattened (no alpha).
    public static func encode(_ image: CIImage, as fileType: ExportPreset.FileType, renderer: RenderService) throws -> Data {
        let data: Data?
        switch fileType {
        case .jpeg:
            let quality = CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String)
            data = renderer.context.jpegRepresentation(of: image, colorSpace: ColorSpaces.sRGB, options: [quality: jpegQuality])
        case .png:
            data = renderer.context.pngRepresentation(of: image, format: .RGBA8, colorSpace: ColorSpaces.sRGB)
        }
        guard let data else { throw ExportError.encodingFailed }
        return data
    }

    /// A readable, collision-free file name, e.g. `CleanCut-Depop-1280x1280-3F2A.jpg`.
    public static func fileName(for preset: ExportPreset, tag: String = String(UUID().uuidString.prefix(4))) -> String {
        "CleanCut-\(preset.name)-\(preset.pixelWidth)x\(preset.pixelHeight)-\(tag).\(preset.fileType.fileExtension)"
    }
}
