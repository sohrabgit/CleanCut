import SwiftUI

/// The one prominent action on a screen.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color.accentColor.opacity(isEnabled ? 1 : 0.4), in: .rect(cornerRadius: Tokens.Radius.medium))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Tokens.Motion.snappy, value: configuration.isPressed)
    }
}

/// Secondary actions: tinted, quiet.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color.accentColor.opacity(0.12), in: .rect(cornerRadius: Tokens.Radius.medium))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Tokens.Motion.snappy, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

/// A selectable capsule, used for formats and shadow styles.
struct Chip: View {
    let title: String
    var subtitle: String?
    var systemImage: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Tokens.Spacing.xxs + 2) {
                if let systemImage {
                    Image(systemName: systemImage).imageScale(.small)
                }
                Text(title).fontWeight(.semibold)
                if let subtitle {
                    Text(subtitle).foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                }
            }
            .font(.subheadline)
            .padding(.horizontal, Tokens.Spacing.s + 2)
            .frame(minHeight: 36)
            .foregroundStyle(isSelected ? .white : .primary)
            .background(
                Capsule().fill(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.fill.tertiary))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(minHeight: Tokens.Size.hitTarget)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

/// A horizontally scrolling row of chips for one choice.
struct ChipPicker<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let title: (Value) -> String
    var subtitle: (Value) -> String? = { _ in nil }
    var systemImage: (Value) -> String? = { _ in nil }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Tokens.Spacing.xs) {
                ForEach(options, id: \.self) { option in
                    Chip(
                        title: title(option),
                        subtitle: subtitle(option),
                        systemImage: systemImage(option),
                        isSelected: option == selection
                    ) {
                        withAnimation(Tokens.Motion.snappy) { selection = option }
                    }
                }
            }
            .padding(.horizontal, Tokens.Spacing.m)
        }
        .scrollIndicators(.hidden)
    }
}

/// A slider with a label and value readout. Reports when a drag ends so the
/// caller can record a single undo step per gesture.
struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var format: (Double) -> String = { "\(Int(($0 * 100).rounded()))%" }
    var onEditingEnded: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
            HStack {
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                Text(format(value))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range) { editing in
                if !editing { onEditingEnded() }
            }
            .accessibilityLabel(title)
            .accessibilityValue(format(value))
        }
    }
}

/// Section title used inside tool panels and sheets.
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A short hint floating over a photo, on a material capsule.
struct HintCapsule: View {
    let systemImage: String
    let text: String
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: Tokens.Spacing.xs) {
            Image(systemName: systemImage)
            Text(text)
            if let onDismiss {
                Button("Dismiss", systemImage: "xmark", action: onDismiss)
                    .labelStyle(.iconOnly)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.footnote.weight(.medium))
        .padding(.horizontal, Tokens.Spacing.m)
        .padding(.vertical, Tokens.Spacing.xs + 2)
        .background(.regularMaterial, in: Capsule())
        .padding(.bottom, Tokens.Spacing.s)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
