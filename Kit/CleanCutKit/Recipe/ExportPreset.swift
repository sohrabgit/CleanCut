import CoreGraphics

/// A marketplace output format.
///
/// Pixel sizes and fill ratios are CleanCut's defaults based on each marketplace's
/// published photo guidance at the time of writing. Marketplaces change these, so
/// they live in this one table (see docs/SPEC.md).
public struct ExportPreset: Identifiable, Hashable, Sendable {
    public enum ID: String, Codable, CaseIterable, Sendable {
        case depop
        case vinted
        case amazon
        case cutout
    }

    public enum FileType: String, Sendable {
        case jpeg
        case png

        public var fileExtension: String { rawValue == "jpeg" ? "jpg" : "png" }
    }

    public let id: ID
    public let name: String
    /// Short label for compact UI, e.g. "1:1".
    public let ratioLabel: String
    public let pixelWidth: Int
    public let pixelHeight: Int
    /// Largest fraction of the canvas width *or* height the subject may occupy.
    public let fill: Double
    public let fileType: FileType
    /// When set, the preset overrides the recipe's background.
    public let requiredBackground: Backdrop?
    public let note: String

    public var pixelSize: CGSize { CGSize(width: pixelWidth, height: pixelHeight) }
    public var aspectRatio: Double { Double(pixelWidth) / Double(pixelHeight) }
    public var supportsTransparency: Bool { fileType == .png }

    public static let depop = ExportPreset(
        id: .depop, name: "Depop", ratioLabel: "1:1",
        pixelWidth: 1280, pixelHeight: 1280, fill: 0.80, fileType: .jpeg,
        requiredBackground: nil,
        note: "Square listing photo."
    )

    public static let vinted = ExportPreset(
        id: .vinted, name: "Vinted", ratioLabel: "4:5",
        pixelWidth: 1200, pixelHeight: 1500, fill: 0.80, fileType: .jpeg,
        requiredBackground: nil,
        note: "Portrait listing photo."
    )

    public static let amazon = ExportPreset(
        id: .amazon, name: "Amazon", ratioLabel: "1:1 white",
        pixelWidth: 2000, pixelHeight: 2000, fill: 0.85, fileType: .jpeg,
        requiredBackground: .solid(.white),
        note: "Main image: pure white (255, 255, 255) background, product fills ~85% of the frame."
    )

    public static let cutout = ExportPreset(
        id: .cutout, name: "Cutout", ratioLabel: "PNG",
        pixelWidth: 2048, pixelHeight: 2048, fill: 0.90, fileType: .png,
        requiredBackground: .transparent,
        note: "Transparent PNG for reuse in other tools."
    )

    public static let all: [ExportPreset] = [.depop, .vinted, .amazon, .cutout]

    public static func preset(for id: ID) -> ExportPreset {
        switch id {
        case .depop: .depop
        case .vinted: .vinted
        case .amazon: .amazon
        case .cutout: .cutout
        }
    }
}
