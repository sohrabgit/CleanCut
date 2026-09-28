import SwiftUI

@main
struct CleanCutApp: App {
    init() {
        // UI tests start from a clean slate (no remembered style or hints).
        if ProcessInfo.processInfo.arguments.contains("-resetState"),
           let domain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    var body: some View {
        HomeView()
    }
}
