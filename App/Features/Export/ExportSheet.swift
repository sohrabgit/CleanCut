import CleanCutKit
import SwiftUI

struct ExportSheet: View {
    let model: EditorModel

    private enum Status: Equatable {
        case idle
        case working(done: Int, total: Int)
        case saved(count: Int)
        case failed(String)
    }

    @State private var selected: Set<ExportPreset.ID>
    @State private var thumbnails: [ExportPreset.ID: UIImage] = [:]
    @State private var status: Status = .idle
    @State private var shareURLs: [URL]?
    @Environment(\.dismiss) private var dismiss

    init(model: EditorModel) {
        self.model = model
        _selected = State(initialValue: [model.recipe.presetID])
    }

    private var isWorking: Bool {
        if case .working = status { true } else { false }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Spacing.s) {
                    Text("Choose one or more formats. Exports are rendered at full quality.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Tokens.Spacing.m)
                    ScrollView(.horizontal) {
                    LazyHStack(spacing: Tokens.Spacing.s) {
                        ForEach(ExportPreset.all) { preset in
                            PresetCard(
                                preset: preset,
                                thumbnail: thumbnails[preset.id],
                                isSelected: selected.contains(preset.id)
                            ) {
                                if selected.contains(preset.id) {
                                    if selected.count > 1 { selected.remove(preset.id) }
                                } else {
                                    selected.insert(preset.id)
                                }
                            }
                            .frame(width: 128)
                        }
                    }
                    .padding(.horizontal, Tokens.Spacing.m)
                    }
                    .scrollIndicators(.hidden)
                }
                .padding(.vertical, Tokens.Spacing.m)
            }
            .safeAreaInset(edge: .bottom) { actions }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await renderThumbnails() }
            .sheet(isPresented: Binding(get: { shareURLs != nil }, set: { if !$0 { shareURLs = nil } })) {
                if let shareURLs { ShareSheet(items: shareURLs).ignoresSafeArea() }
            }
            .sensoryFeedback(.success, trigger: status) { _, new in
                if case .saved = new { true } else { false }
            }
        }
        .presentationDetents([.height(460), .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isWorking)
    }

    private var actions: some View {
        VStack(spacing: Tokens.Spacing.s) {
            statusLine
            HStack(spacing: Tokens.Spacing.s) {
                Button {
                    Task { await share() }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.secondary)
                .frame(width: 64)
                .accessibilityLabel("Share")
                .disabled(isWorking)

                Button {
                    Task { await save() }
                } label: {
                    Label(saveTitle, systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.primary)
                .disabled(isWorking)
            }
        }
        .padding(Tokens.Spacing.m)
        .background(.bar)
    }

    private var saveTitle: String {
        selected.count == 1 ? "Save to Photos" : "Save \(selected.count) Photos"
    }

    @ViewBuilder
    private var statusLine: some View {
        switch status {
        case .idle:
            EmptyView()
        case .working(let done, let total):
            ProgressView(value: Double(done), total: Double(total)) {
                Text("Rendering \(min(done + 1, total)) of \(total)…").font(.footnote)
            }
        case .saved(let count):
            Label(count == 1 ? "Saved to Photos" : "\(count) photos saved to Photos", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
                .transition(.scale.combined(with: .opacity))
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.orange)
        }
    }

    // MARK: - Work

    private var selectedPresets: [ExportPreset] {
        ExportPreset.all.filter { selected.contains($0.id) }
    }

    private func renderThumbnails() async {
        guard let photo = model.photo else { return }
        for preset in ExportPreset.all {
            if let image = await Self.thumbnail(photo: photo, recipe: model.recipe, preset: preset, renderer: model.renderer) {
                thumbnails[preset.id] = UIImage(cgImage: image)
            }
        }
    }

    @concurrent
    private static func thumbnail(photo: PreparedPhoto, recipe: Recipe, preset: ExportPreset, renderer: RenderService) async -> CGImage? {
        guard let inputs = photo.previewInputs(selection: recipe.selectedInstances) else { return nil }
        var recipe = recipe
        recipe.presetID = preset.id
        let scale = 360 / max(preset.pixelSize.width, preset.pixelSize.height)
        let size = CGSize(width: (preset.pixelSize.width * scale).rounded(), height: (preset.pixelSize.height * scale).rounded())
        return renderer.makeCGImage(Pipeline.makeImage(inputs, recipe: recipe, outputSize: size))
    }

    /// Renders every selected preset at full quality into temporary files.
    private func renderFiles() async throws -> [URL] {
        guard let photo = model.photo else { return [] }
        let presets = selectedPresets
        var urls: [URL] = []
        for (index, preset) in presets.enumerated() {
            withAnimation { status = .working(done: index, total: presets.count) }
            urls.append(try await Self.renderFile(photo: photo, recipe: model.recipe, preset: preset, renderer: model.renderer))
        }
        return urls
    }

    @concurrent
    private static func renderFile(photo: PreparedPhoto, recipe: Recipe, preset: ExportPreset, renderer: RenderService) async throws -> URL {
        let data = try Exporter.export(photo, recipe: recipe, preset: preset, renderer: renderer)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(Exporter.fileName(for: preset))
        try data.write(to: url)
        return url
    }

    private func save() async {
        do {
            guard await PhotoLibrary.requestAddAccess() else {
                status = .failed("Allow CleanCut to add photos in Settings to save your exports.")
                return
            }
            let urls = try await renderFiles()
            try await PhotoLibrary.save(urls)
            withAnimation(Tokens.Motion.spring) { status = .saved(count: urls.count) }
        } catch {
            status = .failed(FriendlyError.message(for: error))
        }
    }

    private func share() async {
        do {
            let urls = try await renderFiles()
            status = .idle
            shareURLs = urls
        } catch {
            status = .failed(FriendlyError.message(for: error))
        }
    }
}

private struct PresetCard: View {
    let preset: ExportPreset
    let thumbnail: UIImage?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                ZStack {
                    RoundedRectangle(cornerRadius: Tokens.Radius.small).fill(.fill.tertiary)
                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFit()
                            .clipShape(.rect(cornerRadius: 4))
                            .padding(Tokens.Spacing.xs)
                            .transition(.opacity)
                    } else {
                        ProgressView()
                    }
                }
                .aspectRatio(1, contentMode: .fit)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(preset.name).font(.subheadline.weight(.semibold))
                        Text(verbatim: "\(preset.pixelWidth)×\(preset.pixelHeight)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(preset.fileType.rawValue.uppercased())
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                }
            }
            .padding(Tokens.Spacing.s)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.medium)
                    .fill(.background.secondary)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            )
            .animation(Tokens.Motion.snappy, value: thumbnail != nil)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(preset.note)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
