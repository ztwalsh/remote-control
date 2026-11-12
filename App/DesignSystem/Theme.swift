import SwiftUI

/// Colors, radii and motion from the HTML prototype (prototype/app.html).
/// Every color has a light and a dark value and follows the app's appearance. The colors come from
/// the theme color chosen in Your TVs: Mono (the original black and white) or one color that tints
/// the accent and, faintly, every surface.
enum Theme {
    private static var palette: Palette { ThemeStore.shared.palette }

    static var background: Color { palette.background }
    static var card: Color { palette.card }
    static var raised: Color { palette.raised }
    static var iconTile: Color { palette.iconTile }
    static let line = Color(light: 0x000000, dark: 0xFFFFFF, lightOpacity: 0.06, darkOpacity: 0.07)
    static let lineStrong = Color(light: 0x000000, dark: 0xFFFFFF, lightOpacity: 0.11, darkOpacity: 0.11)
    static var text: Color { palette.text }
    static var muted: Color { palette.muted }
    static var mutedNumber: Color { palette.mutedNumber }
    static var track: Color { palette.track }
    static var mutedFill: Color { palette.mutedFill }
    /// The highlight: the theme color, or in Mono white in dark mode and near-black in light mode.
    static var accent: Color { palette.accent }
    /// Text and icons drawn on `accent`.
    static var onAccent: Color { palette.onAccent }
    /// Removing things.
    static let danger = Color(light: 0xD70015, dark: 0xFF453A)
    /// The power button in a TV row while the TV is off.
    static var offFill: Color { palette.offFill }
    static var offGlyph: Color { palette.offGlyph }

    static let cardRadius: CGFloat = 26

    /// Bubbly: overshoots a little. Used for swells and presses.
    static let bounce = Animation.spring(response: 0.42, dampingFraction: 0.6)
    /// Calm: settles without overshoot. Used for fills and layout.
    static let settle = Animation.spring(response: 0.45, dampingFraction: 0.88)
}

/// Light, dark, or following the phone. Chosen with the switch at the bottom of Your TVs.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var icon: Icon {
        switch self {
        case .system: return .system
        case .light: return .sun
        case .dark: return .moon
        }
    }
}

extension Color {
    /// A color that switches with light and dark mode.
    init(light: UInt32, dark: UInt32, lightOpacity: Double = 1, darkOpacity: Double = 1) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark, opacity: darkOpacity)
                : UIColor(hex: light, opacity: lightOpacity)
        })
    }

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

extension UIColor {
    convenience init(hex: UInt32, opacity: Double = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: opacity
        )
    }
}

private struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

extension View {
    /// The margins every sheet uses around its content.
    func sheetPadding() -> some View {
        padding(.horizontal, 28).padding(.top, 32)
    }

    /// The rounded card used for Volume and Favorites.
    func card() -> some View { modifier(CardStyle()) }
}

/// A small round grey button, used for mute and closing sheets.
struct RoundIconButton: View {
    let icon: Icon
    let label: String
    var isOn = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            IconView(icon, size: 20)
                .frame(width: 38, height: 38)
                .background(isOn ? Theme.text : Theme.raised, in: Circle())
                .foregroundStyle(isOn ? Theme.background : Theme.text)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// The grey pill used for Undo and Cancel timer.
struct PillButton: View {
    let title: String
    let icon: Icon
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            IconLabel(title: title, icon: icon)
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
/// A solid reverse (the accent) so it stands out on the card in both modes.
struct ValueTip: View {
    let text: String

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(Theme.onAccent).frame(width: 8, height: 8)
                Text(text)
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.onAccent)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Caret()
                .fill(Theme.accent)
                .frame(width: 12, height: 6)
        }
        .fixedSize()
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
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
