import CleanCutKit
import PhotosUI
import SwiftUI

struct HomeView: View {
    @State private var pickerItem: PhotosPickerItem?
    @State private var editorSource: PhotoSource?
    @State private var isShowingCamera = false
    @State private var isShowingBatch = false
    @State private var isShowingSettings = false
    @State private var isLoadingPick = false

    private let samples = SampleLibrary.all

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Spacing.xl) {
                    header
                    AddPhotoCard(
                        pickerItem: $pickerItem,
                        isLoading: isLoadingPick,
                        onCamera: CameraPicker.isAvailable ? { isShowingCamera = true } : nil
                    )
                    if !samples.isEmpty { sampleRow }
                    batchRow
                    privacyNote
                }
                .padding(.horizontal, Tokens.Spacing.m)
                .padding(.bottom, Tokens.Spacing.xl)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("CleanCut")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { isShowingSettings = true }
                }
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await open(item) }
        }
        .fullScreenCover(item: $editorSource) { source in
            EditorView(source: source)
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraPicker { image in
                if let data = image.jpegData(compressionQuality: 0.95) {
                    editorSource = .data(data)
                }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $isShowingBatch) {
            BatchView()
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
            Text("Studio photos for your listings")
                .font(.title2.bold())
            Text("Remove the background, add a natural shadow and export for Depop, Vinted or Amazon in seconds.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, Tokens.Spacing.xs)
    }

    private var sampleRow: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s) {
            SectionLabel(text: "Try a sample")
            ScrollView(.horizontal) {
                HStack(spacing: Tokens.Spacing.s) {
                    ForEach(samples) { sample in
                        Button {
                            editorSource = .sample(sample)
                        } label: {
                            SampleThumbnail(sample: sample)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Sample: \(sample.title)")
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private var batchRow: some View {
        Button {
            isShowingBatch = true
        } label: {
            HStack(spacing: Tokens.Spacing.m) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.title2)
                    .foregroundStyle(.accent)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor.opacity(0.12), in: .rect(cornerRadius: Tokens.Radius.medium))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Batch edit").font(.headline)
                    Text("Apply your style to up to 50 photos at once")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(Tokens.Spacing.m)
            .background(.background, in: .rect(cornerRadius: Tokens.Radius.large))
            .contentShape(.rect(cornerRadius: Tokens.Radius.large))
        }
        .buttonStyle(.plain)
    }

    private var privacyNote: some View {
        Label("Everything happens on your device. Photos are never uploaded.", systemImage: "lock.shield")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private func open(_ item: PhotosPickerItem) async {
        isLoadingPick = true
        defer {
            isLoadingPick = false
            pickerItem = nil
        }
        if let data = try? await item.loadTransferable(type: Data.self) {
            editorSource = .data(data)
        }
    }
}

/// The hero call to action.
private struct AddPhotoCard: View {
    @Binding var pickerItem: PhotosPickerItem?
    let isLoading: Bool
    let onCamera: (() -> Void)?

    var body: some View {
        VStack(spacing: Tokens.Spacing.l) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.12)).frame(width: 88, height: 88)
                if isLoading {
                    ProgressView().controlSize(.large)
                } else {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(.accent)
                }
            }
            VStack(spacing: Tokens.Spacing.xxs) {
                Text("Add a product photo").font(.title3.bold())
                Text("Any background works. Keep the whole product in frame.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: Tokens.Spacing.s) {
                PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                    Label("Choose from Photos", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.primary)
                if let onCamera {
                    Button(action: onCamera) {
                        Label("Take Photo", systemImage: "camera")
                    }
                    .buttonStyle(.secondary)
                }
            }
        }
        .padding(Tokens.Spacing.l)
        .frame(maxWidth: .infinity)
        .background(.background, in: .rect(cornerRadius: Tokens.Radius.card))
        .disabled(isLoading)
    }
}

private struct SampleThumbnail: View {
    let sample: SamplePhoto
    @State private var image: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
            ZStack {
                RoundedRectangle(cornerRadius: Tokens.Radius.medium).fill(.fill.tertiary)
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .frame(width: 104, height: 104)
            .clipShape(.rect(cornerRadius: Tokens.Radius.medium))
            Text(sample.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 104, alignment: .leading)
        }
        .task {
            image = await Self.thumbnail(sample.imageURL)
        }
    }

    @concurrent
    private static func thumbnail(_ url: URL) async -> UIImage? {
        (try? ImageLoader.load(url: url, maxPixelSize: 320)).map(UIImage.init(cgImage:))
    }
}
