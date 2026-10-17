import SwiftUI

/// One row in the TV and Sound out pickers: icon tile, name, optional detail, and a 46-point slot on the right.
struct ChoiceRow<Trailing: View>: View {
    let systemImage: String
    let title: String
    var subtitle: String?
    let isSelected: Bool
    let action: () -> Void
    let trailing: Trailing

    init(
        systemImage: String,
        title: String,
        subtitle: String? = nil,
        isSelected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.systemImage = systemImage
        self.title = title
        self.subtitle = subtitle
        self.isSelected = isSelected
        self.action = action
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: action) {
                HStack(spacing: 14) {
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: 42, height: 42)
                        .background(
                            isSelected ? Theme.blue.opacity(0.16) : Theme.iconTile,
                            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                        )
                        .foregroundStyle(isSelected ? Theme.blue : Theme.muted)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.muted)
                                .lineLimit(1)
                                .contentTransition(.opacity)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle())

            trailing.frame(width: 46, height: 46)
        }
        .padding(6)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(isSelected ? Theme.blue : .clear, lineWidth: 1.5)
        )
        .animation(.easeOut(duration: 0.25), value: isSelected)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The selection circle for Sound out: an empty ring that springs into a blue check.
struct RadioMark: View {
    let isOn: Bool

    var body: some View {
        ZStack {
            Circle().strokeBorder(isOn ? Theme.blue : Theme.mutedFill, lineWidth: 2)
            Circle().fill(Theme.blue).opacity(isOn ? 1 : 0)
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(.white)
                .scaleEffect(isOn ? 1 : 0.4)
                .opacity(isOn ? 1 : 0)
        }
        .frame(width: 24, height: 24)
        .scaleEffect(isOn ? 1.05 : 1)
        .animation(Theme.bounce, value: isOn)
    }
}

/// The power button in each TV row: blue when the TV is on.
struct RowPowerButton: View {
    let isOn: Bool
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "power")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 46, height: 46)
                .background(isOn ? Theme.blue : Color(hex: 0x2C2C30), in: Circle())
                .foregroundStyle(isOn ? .white : Color(hex: 0xC9C9CE))
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
