import CleanCutKit
import PhotosUI
import SwiftUI

/// Settings › Benchmarks: measures segmentation, the live preview and guided
/// capture's analysis on this device, and shares the report.
struct LabView: View {
    @State private var model = LabModel()
    @State private var pickerItems: [PhotosPickerItem] = []
    /// The canvas is about as wide as the screen; frames are timed at that size.
    @State private var previewSide = 1206
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Form {
            Section {
                LabeledContent("Photos", value: "\(model.photoCount)")
                PhotosPicker(selection: $pickerItems, maxSelectionCount: 12, matching: .images) {
                    Label("Add Photos", systemImage: "photo.badge.plus")
                }
                .disabled(model.isRunning)
            } footer: {
                Text("The bundled samples plus any photos you add. Photos without a detectable product are skipped. Nothing leaves the device.")
            }

            Section {
                Button(model.isRunning ? "Running…" : "Run Benchmarks") {
                    Task { await model.run(previewSide: previewSide) }
                }
                .buttonStyle(.primary)
                .disabled(model.isRunning || model.photoCount == 0)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } footer: {
                Text("Takes a minute or two. Keep the app open; the screen stays on until it finishes.")
            }

            switch model.phase {
            case .idle:
                EmptyView()
            case .running(let step, let progress):
                Section("Progress") {
                    ProgressView(value: progress) {
                        Text(step)
                    }
                    .accessibilityValue("\(Int(progress * 100)) percent, \(step)")
                }
            case .failed(let message):
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            case .finished(let report, let files):
                LabResults(report: report, files: files)
            }
        }
        .navigationTitle("Benchmarks")
        .navigationBarTitleDisplayMode(.inline)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { previewSide = Int(($0 * displayScale).rounded()) }
        .onChange(of: pickerItems) { _, items in
            Task {
                var photos: [Data] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) { photos.append(data) }
                }
                model.setPickedPhotos(photos)
            }
        }
        .task {
            if LabModel.runsOnLaunch { await model.run(previewSide: previewSide) }
        }
    }
}

private struct LabResults: View {
    let report: DeviceBenchmarkReport
    let files: [URL]

    var body: some View {
        Section {
            ForEach(report.segmentation, id: \.rowID) { result in
                LabeledContent(result.rowID, value: result.error == nil ? Self.ms(result.inferenceP50MS) : "Unsupported")
            }
        } header: {
            Text("Segmentation, inference p50")
        } footer: {
            Text("\(report.photoCount) photos, 30 runs per row.")
        }

        Section {
            ForEach(report.preview, id: \.scenario) { row in
                LabeledContent(row.scenario, value: Self.ms(row.frameP90MS))
            }
        } header: {
            Text("Live preview, frame p90")
        } footer: {
            Text("\(Int(report.previewSize.width)) px square. Budget: 16.7 ms at 60 Hz.")
        }

        if let capture = report.capture {
            Section {
                LabeledContent("Frame statistics", value: Self.ms(capture.analysisP50MS))
                LabeledContent("Subject mask", value: capture.maskP50MS.map(Self.ms) ?? "–")
                LabeledContent("Per frame, mean", value: Self.ms(capture.frameMeanMS))
            } header: {
                Text("Guided capture, p50")
            } footer: {
                Text(String(format: "Budget at 15 fps: %.1f ms per frame.", CaptureBenchmark.budgetMS))
            }
        }

        Section {
            LabeledContent("Device", value: report.machine)
            LabeledContent("Thermal state", value: "\(report.thermalStateAtStart) → \(report.thermalStateAtEnd)")
            ShareLink(items: files) {
                Label("Share Report", systemImage: "square.and.arrow.up")
            }
        }
    }

    private static func ms(_ value: Double) -> String {
        value >= 100 ? String(format: "%.0f ms", value) : String(format: "%.1f ms", value)
    }
}

private extension BenchmarkResult {
    var rowID: String { "\(engine) · \(compute)" }
}
