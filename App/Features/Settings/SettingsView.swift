import SwiftUI

struct SettingsView: View {
    @AppStorage("showPerformanceHUD") private var showHUD = false
    @AppStorage(SegmentationEngine.storageKey) private var engine: SegmentationEngine = .vision
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
                    Picker("Engine", selection: $engine) {
                        ForEach(SegmentationEngine.allCases) { engine in
                            Text(engine.title).tag(engine)
                        }
                    }
                } header: {
                    Text("Background removal")
                } footer: {
                    Text(engine.detail)
                }

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
                    NavigationLink("Acknowledgements") { AcknowledgementsView() }
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

private struct AcknowledgementsView: View {
    var body: some View {
        List {
            Section {
                Text("U²-Net / U²-Netp — Xuebin Qin, Zichen Zhang, Chenyang Huang, Masood Dehghan, Osmar R. Zaiane and Martin Jagersand. Apache License 2.0.")
                Link("github.com/xuebinqin/U-2-Net", destination: URL(string: "https://github.com/xuebinqin/U-2-Net")!)
            } header: {
                Text("Segmentation model")
            }
        }
        .navigationTitle("Acknowledgements")
        .font(.footnote)
    }
}
