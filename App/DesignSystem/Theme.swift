import SwiftUI

/// Colors, radii and motion from the HTML prototype (prototype/lg-remote.html).
enum Theme {
    static let background = Color(hex: 0x0B0B0C)
    static let card = Color(hex: 0x141415)
    static let raised = Color(hex: 0x1D1D1F)
    static let iconTile = Color(hex: 0x2A2A2E)
    static let line = Color.white.opacity(0.07)
    static let lineStrong = Color.white.opacity(0.11)
    static let text = Color(hex: 0xF2F2F3)
    static let muted = Color(hex: 0x8B8B90)
    static let mutedNumber = Color(hex: 0x5E5E63)
    static let track = Color(hex: 0x2A2A2D)
    static let trackAlt = Color(hex: 0x303034)
    static let mutedFill = Color(hex: 0x4A4A4E)
    static let tooltip = Color(hex: 0x161618)
    static let blue = Color(hex: 0x0A84FF)

    static let cardRadius: CGFloat = 26

    /// Bubbly: overshoots a little. Used for swells and presses.
    static let bounce = Animation.spring(response: 0.42, dampingFraction: 0.6)
    /// Calm: settles without overshoot. Used for fills and layout.
    static let settle = Animation.spring(response: 0.45, dampingFraction: 0.88)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

private struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.line))
    }
}

extension View {
    /// The dark rounded card used for Volume and Favorites.
    func card() -> some View { modifier(CardStyle()) }
}

/// A small round grey button, used for mute and closing sheets.
struct RoundIconButton: View {
    let systemImage: String
    let label: String
    var isOn = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 38, height: 38)
                .background(isOn ? Theme.text : Theme.raised, in: Circle())
                .foregroundStyle(isOn ? Theme.background : Theme.text)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// The grey pill used for Undo and Cancel timer.
struct PillButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 15))
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(Theme.raised, in: Capsule())
                .foregroundStyle(Theme.text)
        }
        .buttonStyle(.plain)
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }
}

/// The floating label with a caret, shown above a bar while it's being dragged.
struct ValueTip: View {
    let text: String

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(Theme.blue).frame(width: 9, height: 9)
                Text(text)
                    .font(.system(size: 14))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Theme.tooltip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.lineStrong))
            Caret()
                .fill(Theme.tooltip)
                .frame(width: 12, height: 6)
        }
        .fixedSize()
    }
}

private struct Caret: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
