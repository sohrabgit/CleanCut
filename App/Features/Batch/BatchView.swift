import SwiftUI

/// Placeholder until batch mode lands (M5).
struct BatchView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContentUnavailableView("Batch edit", systemImage: "square.stack.3d.up", description: Text("Coming soon."))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                }
        }
    }
}
