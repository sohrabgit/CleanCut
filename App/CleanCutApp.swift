import SwiftUI

@main
struct CleanCutApp: App {
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
