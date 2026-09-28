import CleanCutKit
import PhotosUI
import SwiftUI

struct BatchView: View {
    @State private var model = BatchModel()
    @State private var picks: [PhotosPickerItem] = []
    @State private var shareURLs: [URL]?
    @State private var saveFailed = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if model.phase == .choosing {
                    emptyState
                } else {
                    content
                }
            }
            .navigationTitle("Batch Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        model.cancel()
                        dismiss()
                    }
                }
                if model.phase == .ready || model.phase == .finished {
                    ToolbarItem(placement: .primaryAction) {
                        PhotosPicker(selection: $picks, maxSelectionCount: BatchModel.maxPhotos, matching: .images) {
                            Text("Change Photos")
                        }
                    }
                }
            }
            .onChange(of: picks) { _, new in model.setPhotos(new) }
            .sheet(isPresented: Binding(get: { shareURLs != nil }, set: { if !$0 { shareURLs = nil } })) {
                if let shareURLs { ShareSheet(items: shareURLs).ignoresSafeArea() }
            }
            .sensoryFeedback(.success, trigger: model.phase) { _, new in new == .finished }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Tokens.Spacing.l) {
            Spacer()
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 52, weight: .medium))
                .foregroundStyle(.accent)
            VStack(spacing: Tokens.Spacing.xs) {
                Text("Edit a whole collection").font(.title2.bold())
                Text("Pick up to \(BatchModel.maxPhotos) photos. CleanCut removes each background and applies your last style: \(model.styleSummary.lowercased()).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            PhotosPicker(selection: $picks, maxSelectionCount: BatchModel.maxPhotos, matching: .images) {
                Label("Choose Photos", systemImage: "photo.on.rectangle.angled")
            }
            .buttonStyle(.primary)
            .frame(maxWidth: 360)
            Spacer()
            Spacer()
        }
        .padding(Tokens.Spacing.l)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Spacing.l) {
                settings
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: Tokens.Spacing.xs)], spacing: Tokens.Spacing.xs) {
                    ForEach(model.items) { item in
                        BatchTile(item: item)
                    }
                }
            }
            .padding(Tokens.Spacing.m)
        }
        .safeAreaInset(edge: .bottom) { actions }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s) {
            HStack {
                Label(model.styleSummary, systemImage: "paintbrush")
                    .font(.subheadline)
                Spacer()
            }
            .padding(Tokens.Spacing.s)
            .background(.fill.quaternary, in: .rect(cornerRadius: Tokens.Radius.medium))

            SectionLabel(text: "Formats")
            HStack(spacing: Tokens.Spacing.xs) {
                ForEach(ExportPreset.all) { preset in
                    Chip(title: preset.name, isSelected: model.presets.contains(preset.id)) {
                        if model.presets.contains(preset.id) {
                            if model.presets.count > 1 { model.presets.remove(preset.id) }
                        } else {
                            model.presets.insert(preset.id)
                        }
                    }
                }
            }
            .disabled(model.phase == .running)
        }
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: Tokens.Spacing.s) {
            switch model.phase {
            case .choosing:
                EmptyView()
            case .ready:
                Button("Process \(model.items.count) Photos") { model.start() }
                    .buttonStyle(.primary)
            case .running:
                ProgressView(value: Double(model.finishedCount), total: Double(max(model.items.count, 1))) {
                    Text("Processing \(min(model.finishedCount + 1, model.items.count)) of \(model.items.count)…")
                        .font(.footnote)
                }
                Button("Cancel", role: .cancel) { model.cancel() }
                    .buttonStyle(.secondary)
            case .finished:
                finishedSummary
                HStack(spacing: Tokens.Spacing.s) {
                    Button {
                        shareURLs = model.outputFiles
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .buttonStyle(.secondary)
                    .frame(width: 64)
                    .accessibilityLabel("Share")
                    .disabled(model.outputFiles.isEmpty)

                    Button {
                        Task { saveFailed = !(await model.saveAll()) }
                    } label: {
                        Label(model.savedCount == nil ? "Save All to Photos" : "Saved", systemImage: model.savedCount == nil ? "square.and.arrow.down" : "checkmark")
                    }
                    .buttonStyle(.primary)
                    .disabled(model.outputFiles.isEmpty || model.savedCount != nil)
                }
                if model.failedCount > 0 {
                    Button("Retry \(model.failedCount) Failed") { model.retryFailed() }
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .padding(Tokens.Spacing.m)
        .background(.bar)
        .alert("Couldn't save to Photos", isPresented: $saveFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Allow CleanCut to add photos in Settings, then try again.")
        }
    }

    private var finishedSummary: some View {
        let done = model.doneCount, failed = model.failedCount
        let files = model.outputFiles.count
        return Label(
            failed == 0 ? "\(done) photos ready · \(files) files" : "\(done) ready · \(failed) couldn't be processed",
            systemImage: failed == 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
        )
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(failed == 0 ? .green : .orange)
    }
}

private struct BatchTile: View {
    let item: BatchModel.Item

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Tokens.Radius.medium).fill(.fill.tertiary)
            if let image = item.result ?? item.thumbnail {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            }
            overlay
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(.rect(cornerRadius: Tokens.Radius.medium))
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var overlay: some View {
        switch item.state {
        case .waiting:
            EmptyView()
        case .processing:
            ZStack {
                Color.black.opacity(0.35)
                ProgressView().tint(.white)
            }
        case .done:
            badge("checkmark.circle.fill", color: .green)
        case .failed:
            ZStack {
                Color.black.opacity(0.45)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.yellow)
            }
        }
    }

    private func badge(_ systemImage: String, color: Color) -> some View {
        VStack {
            HStack {
                Spacer()
                Image(systemName: systemImage)
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, color)
                    .padding(Tokens.Spacing.xxs + 2)
            }
            Spacer()
        }
    }

    private var accessibilityText: String {
        switch item.state {
        case .waiting: "Waiting"
        case .processing: "Processing"
        case .done: "Done"
        case .failed(let message): "Failed: \(message)"
        }
    }
}
