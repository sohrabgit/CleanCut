import CleanCutKit
import Foundation
import Photos

/// Remembers the last style the user applied, so the next photo (and batch
/// mode) starts from it. The object selection is per photo and isn't kept.
enum StyleStore {
    private static let key = "lastRecipe"

    static func load() -> Recipe {
        guard let data = UserDefaults.standard.data(forKey: key),
              var recipe = try? JSONDecoder().decode(Recipe.self, from: data)
        else { return .default }
        recipe.selectedInstances = nil
        return recipe.clamped()
    }

    static func save(_ recipe: Recipe) {
        var recipe = recipe
        recipe.selectedInstances = nil
        if let data = try? JSONEncoder().encode(recipe) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

/// User-facing error copy. Never show raw error descriptions.
enum FriendlyError {
    static func message(for error: any Error) -> String {
        switch error {
        case SegmentationError.noSubject:
            "No product found. Try a photo with one clear subject and some space around it."
        case SegmentationError.unavailable:
            "Background removal needs an iPhone, iPad or Mac. In the Simulator, try one of the samples."
        case is ImageLoader.LoadError:
            "This photo couldn't be opened. Try a JPEG, HEIC or PNG."
        case Exporter.ExportError.nothingSelected:
            "Select at least one object to export."
        default:
            "Something went wrong while processing this photo. Please try again."
        }
    }
}

/// Adds rendered files to the user's photo library.
///
/// `nonisolated` on purpose: Photos runs the change block on its own queue.
/// Written inside a `MainActor` view or model, the closure would inherit that
/// isolation, and Swift's runtime check traps when Photos calls it off the
/// main thread.
nonisolated enum PhotoLibrary {
    static func requestAddAccess() async -> Bool {
        await PHPhotoLibrary.requestAuthorization(for: .addOnly) == .authorized
    }

    static func save(_ urls: [URL]) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            for url in urls {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: url, options: nil)
            }
        }
    }
}
