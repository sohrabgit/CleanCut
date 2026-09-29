import CleanCutKit
import CoreImage
import SwiftUI

/// Where the photo being edited comes from.
enum PhotoSource: Identifiable {
    case data(Data)
    case sample(SamplePhoto)

    var id: String {
        switch self {
        case .data(let data): "data-\(data.count)-\(data.hashValue)"
        case .sample(let sample): "sample-\(sample.name)"
        }
    }
}

/// A photo bundled with the app, with instance masks precomputed by Vision on
/// a Mac (`cleancut-bench masks`), so the full flow also works in the Simulator,
/// where Vision's foreground instance mask can't run.
struct SamplePhoto: Identifiable, Hashable {
    let name: String
    let imageURL: URL
    let maskURLs: [URL]

    var id: String { name }

    var title: String {
        name.replacingOccurrences(of: "-", with: " ").capitalized
    }

    /// Loads the precomputed masks as non-color-managed coverage images.
    func masks() -> [CIImage] {
        maskURLs.compactMap { CIImage(contentsOf: $0, options: [.colorSpace: NSNull()]) }
    }
}

/// Samples live in `App/Resources/Samples` as `<name>.jpg` plus
/// `<name>.masks/<instance>.png`.
enum SampleLibrary {
    /// Local dev samples (`local-*`, git-ignored) may be third-party images,
    /// so recordings that get committed (the demo GIF) launch with
    /// `-hideLocalSamples` to leave them out.
    private static let hidesLocalSamples = ProcessInfo.processInfo.arguments.contains("-hideLocalSamples")

    static let all: [SamplePhoto] = {
        guard let root = Bundle.main.url(forResource: "Samples", withExtension: nil),
              let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        else { return [] }
        return files
            .filter { ["jpg", "jpeg", "heic", "png"].contains($0.pathExtension.lowercased()) }
            .filter { !hidesLocalSamples || !$0.lastPathComponent.hasPrefix("local-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { url in
                let name = url.deletingPathExtension().lastPathComponent
                let maskDir = root.appendingPathComponent("\(name).masks", isDirectory: true)
                let masks = ((try? FileManager.default.contentsOfDirectory(at: maskDir, includingPropertiesForKeys: nil)) ?? [])
                    .filter { $0.pathExtension == "png" }
                    .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                return SamplePhoto(name: name, imageURL: url, maskURLs: masks)
            }
    }()
}
