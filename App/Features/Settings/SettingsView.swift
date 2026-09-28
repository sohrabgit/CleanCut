import SwiftUI

struct SettingsView: View {
    @AppStorage("showPerformanceHUD") private var showHUD = false
    @Environment(\.dismiss) private var dismiss

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Show frame timing", isOn: $showHUD)
                } header: {
                    Text("Developer")
                } footer: {
                    Text("Overlays GPU and CPU time per preview frame on the editor canvas.")
                }

                Section("About") {
                    LabeledContent("Version", value: version)
                    LabeledContent("Processing", value: "On device")
                    Link(destination: URL(string: "https://github.com/sohrabgit/CleanCut")!) {
                        Label("Source code", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
