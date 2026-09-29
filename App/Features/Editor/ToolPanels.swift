import CleanCutKit
import SwiftUI

/// Marketplace formats as a segmented control. Switching reframes the canvas live.
struct FormatBar: View {
    @Bindable var model: EditorModel
    @Namespace private var selection

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ExportPreset.all) { preset in
                let isSelected = model.recipe.presetID == preset.id
                Button {
                    withAnimation(Tokens.Motion.snappy) {
                        model.update { $0.presetID = preset.id }
                    }
                } label: {
                    VStack(spacing: 1) {
                        Text(preset.name).font(.subheadline.weight(.semibold))
                        Text(preset.ratioLabel).font(.caption2.weight(.medium))
                            .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                    }
                    .foregroundStyle(isSelected ? .white : .primary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: Tokens.Radius.small + 2)
                                .fill(Color.accentColor)
                                .matchedGeometryEffect(id: "format", in: selection)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(preset.name), \(preset.pixelWidth) by \(preset.pixelHeight)")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(.fill.tertiary, in: .rect(cornerRadius: Tokens.Radius.medium))
        .padding(.horizontal, Tokens.Spacing.m)
        .sensoryFeedback(.selection, trigger: model.recipe.presetID)
    }
}

/// The bottom tool tray (compact) or inspector section (regular width).
struct ToolTray: View {
    enum Layout { case tray, inspector }

    @Bindable var model: EditorModel
    var layout: Layout = .tray

    var body: some View {
        switch layout {
        case .tray:
            VStack(spacing: 0) {
                panel
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.vertical, Tokens.Spacing.s)
                Divider()
                tabs
            }
            .background(.bar)
        case .inspector:
            VStack(alignment: .leading, spacing: Tokens.Spacing.m) {
                tabs.padding(.horizontal, Tokens.Spacing.xs)
                panel
            }
        }
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            ForEach(EditorModel.Tool.allCases) { tool in
                Button {
                    withAnimation(Tokens.Motion.snappy) { model.tool = tool }
                } label: {
                    VStack(spacing: Tokens.Spacing.xxs) {
                        Image(systemName: tool.systemImage)
                            .font(.system(size: 19, weight: .medium))
                            .frame(height: 24)
                        Text(tool.title).font(.caption2.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(model.tool == tool ? Color.accentColor : .secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(model.tool == tool ? .isSelected : [])
                .sensoryFeedback(.selection, trigger: model.tool)
            }
        }
        .padding(.bottom, layout == .tray ? Tokens.Spacing.xxs : 0)
    }

    @ViewBuilder
    private var panel: some View {
        switch model.tool {
        case .select: SelectPanel(model: model)
        case .background: BackgroundPanel(model: model)
        case .shadow: ShadowPanel(model: model)
        case .edges: EdgesPanel(model: model)
        }
    }
}

// MARK: - Select

private struct SelectPanel: View {
    @Bindable var model: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s) {
            Text(model.instances.count > 1
                 ? "\(model.instances.count) objects found. Tap one on the photo, or below, to include or exclude it."
                 : "One product found. It's ready to go.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Tokens.Spacing.m)

            ScrollView(.horizontal) {
                HStack(spacing: Tokens.Spacing.xs) {
                    Chip(title: "All objects", systemImage: "square.stack.3d.up", isSelected: model.recipe.selectedInstances == nil) {
                        model.selectAll()
                    }
                    ForEach(model.instances, id: \.self) { instance in
                        Chip(
                            title: "Object \(instance)",
                            systemImage: model.isSelected(instance) ? "checkmark.circle.fill" : "circle",
                            isSelected: model.isSelected(instance) && model.recipe.selectedInstances != nil
                        ) {
                            model.toggle(instance)
                        }
                        .accessibilityValue(model.isSelected(instance) ? "Included" : "Excluded")
                    }
                }
                .padding(.horizontal, Tokens.Spacing.m)
            }
            .scrollIndicators(.hidden)
        }
    }
}

// MARK: - Background

private struct BackgroundPanel: View {
    @Bindable var model: EditorModel

    private struct Swatch: Identifiable {
        let name: String
        let style: Backdrop
        var id: String { name }
    }

    private let swatches: [Swatch] = [
        Swatch(name: "White", style: .solid(.white)),
        Swatch(name: "Paper", style: .solid(RGBA(hex: 0xF6F3EE))),
        Swatch(name: "Studio", style: .studioSweep(RGBA(hex: 0xEDEBE8))),
        Swatch(name: "Sand", style: .solid(RGBA(hex: 0xEDE3D3))),
        Swatch(name: "Mist", style: .solid(RGBA(hex: 0xE3E9EF))),
        Swatch(name: "Sage", style: .solid(RGBA(hex: 0xDDE5DA))),
        Swatch(name: "Clear", style: .transparent),
    ]

    var body: some View {
        if let required = model.recipe.preset.requiredBackground {
            LockedNote(
                text: required == .transparent
                    ? "Cutout exports a transparent PNG, so there's no background."
                    : "\(model.recipe.preset.name) main images need a pure white background, so it's locked to white."
            )
        } else {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: Tokens.Spacing.s) {
                    ForEach(swatches) { swatch in
                        SwatchButton(name: swatch.name, style: swatch.style, isSelected: model.recipe.background == swatch.style) {
                            model.update { $0.background = swatch.style }
                        }
                    }
                    customColor
                }
                .padding(.horizontal, Tokens.Spacing.m)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var customColor: some View {
        VStack(spacing: Tokens.Spacing.xxs + 2) {
            ColorPicker("Custom color", selection: customBinding, supportsOpacity: false)
                .labelsHidden()
                .frame(width: Tokens.Size.swatch, height: Tokens.Size.swatch)
            Text("Custom").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var customBinding: Binding<Color> {
        Binding(
            get: {
                let color = model.recipe.background.baseColor ?? .white
                return Color(.sRGB, red: color.red, green: color.green, blue: color.blue)
            },
            set: { color in
                let resolved = color.resolve(in: EnvironmentValues())
                let rgba = RGBA(red: Double(resolved.red), green: Double(resolved.green), blue: Double(resolved.blue))
                model.update { $0.background = .solid(rgba) }
            }
        )
    }
}

private struct SwatchButton: View {
    let name: String
    let style: Backdrop
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Tokens.Spacing.xxs + 2) {
                fill
                    .frame(width: Tokens.Size.swatch, height: Tokens.Size.swatch)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(.primary.opacity(0.12), lineWidth: 1))
                    .padding(3)
                    .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: isSelected ? 2.5 : 0))
                Text(name)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name) background")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var fill: some View {
        switch style {
        case .solid(let color):
            Color(.sRGB, red: color.red, green: color.green, blue: color.blue)
        case .studioSweep(let color):
            LinearGradient(
                colors: [color.adjustingBrightness(0.1).swiftUIColor, color.adjustingBrightness(-0.12).swiftUIColor],
                startPoint: .top, endPoint: .bottom
            )
        case .transparent:
            Checkerboard()
        }
    }
}

private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 8
            for row in 0..<Int(size.height / cell) + 1 {
                for column in 0..<Int(size.width / cell) + 1 where (row + column).isMultiple(of: 2) {
                    context.fill(Path(CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell)), with: .color(.gray.opacity(0.25)))
                }
            }
        }
        .background(.white)
    }
}

private struct LockedNote: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "lock.fill")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, Tokens.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Shadow

private struct ShadowPanel: View {
    @Bindable var model: EditorModel
    @State private var showsAdjust = false

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s) {
            ChipPicker(
                options: ShadowSettings.Kind.allCases,
                selection: Binding(
                    get: { model.recipe.shadow.kind },
                    set: { kind in model.update { $0.shadow.kind = kind } }
                ),
                title: \.title
            )

            if model.recipe.shadow.kind != .none {
                HStack(alignment: .bottom, spacing: Tokens.Spacing.m) {
                    LabeledSlider(title: "Intensity", value: $model.recipe.shadow.intensity, onEditingEnded: model.commit)
                    AdjustToggle(isOn: $showsAdjust)
                }
                .padding(.horizontal, Tokens.Spacing.m)

                if showsAdjust {
                    VStack(spacing: Tokens.Spacing.s) {
                        if model.recipe.shadow.kind.hasDrop {
                            LabeledSlider(
                                title: "Direction", value: $model.recipe.shadow.angle, range: 180...360,
                                format: { "\(Int($0))°" }, onEditingEnded: model.commit
                            )
                            LabeledSlider(
                                title: "Distance", value: $model.recipe.shadow.distance, range: ShadowSettings.distanceRange,
                                format: { "\(Int($0 / ShadowSettings.distanceRange.upperBound * 100))%" }, onEditingEnded: model.commit
                            )
                            LabeledSlider(
                                title: "Softness", value: $model.recipe.shadow.softness, range: ShadowSettings.softnessRange,
                                format: { "\(Int($0 / ShadowSettings.softnessRange.upperBound * 100))%" }, onEditingEnded: model.commit
                            )
                        } else {
                            Text("A contact shadow sits right where the product touches the floor.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, Tokens.Spacing.m)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .animation(Tokens.Motion.snappy, value: showsAdjust)
        .animation(Tokens.Motion.snappy, value: model.recipe.shadow.kind)
    }
}

// MARK: - Edges

private struct EdgesPanel: View {
    @Bindable var model: EditorModel
    @State private var showsAdjust = false

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s) {
            Toggle(isOn: Binding(
                get: { model.recipe.edges.cleanEdges },
                set: { value in model.update { $0.edges.cleanEdges = value } }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Clean edges").font(.subheadline.weight(.medium))
                    Text("Removes color from the old background around the product.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .bottom, spacing: Tokens.Spacing.m) {
                LabeledSlider(title: "Strength", value: $model.recipe.edges.cleanStrength, onEditingEnded: model.commit)
                    .disabled(!model.recipe.edges.cleanEdges)
                AdjustToggle(isOn: $showsAdjust)
            }

            if showsAdjust {
                LabeledSlider(
                    title: "Soften edges", value: $model.recipe.edges.feather, range: EdgeSettings.featherRange,
                    format: { "\(Int($0 / EdgeSettings.featherRange.upperBound * 100))%" }, onEditingEnded: model.commit
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.horizontal, Tokens.Spacing.m)
        .animation(Tokens.Motion.snappy, value: showsAdjust)
    }
}

/// Reveals the finer controls of a panel.
private struct AdjustToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.body.weight(.medium))
                .frame(width: 36, height: 36)
                .foregroundStyle(isOn ? .white : .primary)
                .background(Circle().fill(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.fill.tertiary)))
        }
        .buttonStyle(.plain)
        .frame(minWidth: Tokens.Size.hitTarget, minHeight: Tokens.Size.hitTarget)
        .accessibilityLabel(isOn ? "Hide adjustments" : "Adjust")
    }
}

extension ShadowSettings.Kind {
    var title: String {
        switch self {
        case .none: "None"
        case .soft: "Soft"
        case .contact: "Contact"
        case .natural: "Natural"
        }
    }
}

extension RGBA {
    var swiftUIColor: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }
}
