import SwiftUI

/// True inside a selected ChoiceRow, whose background is the solid accent.
/// Controls in the row's trailing slot flip their colors to stay visible.
private struct InvertedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isInverted: Bool {
        get { self[InvertedKey.self] }
        set { self[InvertedKey.self] = newValue }
    }
}

/// One row in the TV and Sound out pickers: icon tile, name, optional detail, and a 46-point slot
/// on the right. The selected row is a full reverse: solid accent background, no border.
struct ChoiceRow<Trailing: View>: View {
    let icon: Icon
    let title: String
    var subtitle: String?
    let isSelected: Bool
    let action: () -> Void
    let trailing: Trailing

    init(
        icon: Icon,
        title: String,
        subtitle: String? = nil,
        isSelected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.isSelected = isSelected
        self.action = action
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: action) {
                HStack(spacing: 14) {
                    IconView(icon, size: 22)
                        .frame(width: 44, height: 44)
                        .background(
                            isSelected ? Theme.onAccent.opacity(0.12) : Theme.iconTile,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                        .foregroundStyle(isSelected ? Theme.onAccent : Theme.muted)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(isSelected ? Theme.onAccent : Theme.text)
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 13))
                                .foregroundStyle(isSelected ? Theme.onAccent.opacity(0.62) : Theme.muted)
                                .lineLimit(1)
                                .contentTransition(.opacity)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle())

            trailing
                .frame(minWidth: 46, minHeight: 46)
                .environment(\.isInverted, isSelected)
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .background(isSelected ? Theme.accent : Theme.raised, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .animation(.easeOut(duration: 0.22), value: isSelected)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The selection circle for Sound out: an empty ring that springs into a blue check.
struct RadioMark: View {
    let isOn: Bool
    @Environment(\.isInverted) private var inverted

    var body: some View {
        let fill = inverted ? Theme.onAccent : Theme.accent
        let mark = inverted ? Theme.accent : Theme.onAccent
        ZStack {
            Circle().fill(inverted ? Theme.onAccent.opacity(0.14) : Theme.iconTile)
            Circle().fill(fill).opacity(isOn ? 1 : 0)
            IconView(.check, size: 16)
                .foregroundStyle(mark)
                .scaleEffect(isOn ? 1 : 0.4)
                .opacity(isOn ? 1 : 0)
        }
        .frame(width: 24, height: 24)
        .scaleEffect(isOn ? 1.05 : 1)
        .animation(Theme.bounce, value: isOn)
    }
}

/// The power button in each TV row: filled with the accent when the TV is on.
struct RowPowerButton: View {
    let isOn: Bool
    let label: String
    let action: () -> Void
    @Environment(\.isInverted) private var inverted

    private var fill: Color {
        if inverted { return isOn ? Theme.onAccent : Theme.onAccent.opacity(0.14) }
        return isOn ? Theme.accent : Theme.offFill
    }

    private var glyph: Color {
        if inverted { return isOn ? Theme.accent : Theme.onAccent }
        return isOn ? Theme.onAccent : Theme.offGlyph
    }

    var body: some View {
        Button(action: action) {
            IconView(.power, size: 22)
                .frame(width: 46, height: 46)
                .background(fill, in: Circle())
                .foregroundStyle(glyph)
        }
        .buttonStyle(PressScaleStyle(scale: 0.9))
        .animation(.easeOut(duration: 0.24), value: isOn)
        .accessibilityLabel(label)
    }
}

/// A springy press: shrinks slightly while held.
struct PressScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.98

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(Theme.bounce, value: configuration.isPressed)
    }
}
