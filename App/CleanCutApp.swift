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
    @State private var isShowingSplash = true

    var body: some View {
        HomeView()
            .overlay {
                if isShowingSplash {
                    SplashView { isShowingSplash = false }
                }
            }
    }
}
