import SwiftUI
import Observation

/// The theme color chosen in Your TVs, kept across launches. Views read it through `Theme`, so
/// changing it redraws everything, open sheets included.
@Observable
final class ThemeStore {
    static let shared = ThemeStore()

    /// The chosen color as 0xRRGGBB, or nil for Mono.
    var tint: UInt32? {
        didSet {
            palette = Palette(tint: tint)
            if let tint { UserDefaults.standard.set(Int(tint), forKey: Self.key) } else { UserDefaults.standard.removeObject(forKey: Self.key) }
        }
    }

    private(set) var palette: Palette

    private static let key = "themeColor"

    private init() {
        let saved = (UserDefaults.standard.object(forKey: Self.key) as? Int).map { UInt32(truncatingIfNeeded: $0) }
        tint = saved
        palette = Palette(tint: saved)
    }

    /// The ready-made choices after Mono. Anything else comes from the color well.
    static let presets: [UInt32] = [0x0A84FF, 0xBF5AF2, 0xFF375F, 0xFF9F0A, 0x30D158]
}

/// Every color the app draws with, for one theme color.
struct Palette {
    var background, card, raised, iconTile, text, muted, mutedNumber, track, mutedFill, offFill, offGlyph: Color
    var accent, onAccent: Color

    init(tint: UInt32?) {
        guard let tint else {
            // Mono: the original greys, with a black or white highlight.
            background = Color(light: 0xF2F2F5, dark: 0x0B0B0C)
            card = Color(light: 0xFFFFFF, dark: 0x141415)
            raised = Color(light: 0xF1F1F3, dark: 0x1D1D1F)
            iconTile = Color(light: 0xE6E6EA, dark: 0x2A2A2E)
            text = Color(light: 0x111113, dark: 0xF2F2F3)
            muted = Color(light: 0x6E6E73, dark: 0x8B8B90)
            mutedNumber = Color(light: 0xA8A8AD, dark: 0x5E5E63)
            track = Color(light: 0xE4E4E8, dark: 0x2A2A2D)
            mutedFill = Color(light: 0xC2C2C7, dark: 0x4A4A4E)
            offFill = Color(light: 0xE2E2E6, dark: 0x2C2C30)
            offGlyph = Color(light: 0x45454A, dark: 0xC9C9CE)
            accent = Color(light: 0x111113, dark: 0xFFFFFF)
            onAccent = Color(light: 0xFFFFFF, dark: 0x0B0B0C)
            return
        }

        let base = UIColor(hex: tint)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        base.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        // A greyish pick tints the surfaces less, so a grey gives plain greys.
        let k = saturation

        /// A neutral with a little of the theme's hue: (saturation, brightness) for light and dark.
        func surface(_ light: (CGFloat, CGFloat), _ dark: (CGFloat, CGFloat)) -> Color {
            Color(light: UIColor(hue: hue, saturation: light.0 * k, brightness: light.1, alpha: 1),
                  dark: UIColor(hue: hue, saturation: dark.0 * k, brightness: dark.1, alpha: 1))
        }

        background = surface((0.07, 0.965), (0.35, 0.055))
        card = surface((0.015, 1.0), (0.28, 0.09))
        raised = surface((0.05, 0.955), (0.24, 0.13))
        iconTile = surface((0.09, 0.915), (0.20, 0.185))
        text = surface((0.30, 0.08), (0.03, 0.96))
        muted = surface((0.15, 0.45), (0.12, 0.60))
        mutedNumber = surface((0.10, 0.70), (0.12, 0.40))
        track = surface((0.10, 0.905), (0.20, 0.175))
        mutedFill = surface((0.12, 0.78), (0.16, 0.31))
        offFill = surface((0.09, 0.895), (0.20, 0.19))
        offGlyph = surface((0.20, 0.29), (0.06, 0.80))

        // The accent is the color itself, deepened on light backgrounds if it's very pale
        // and lifted on dark ones if it's very deep, so it always stands out.
        let lightAccent = Self.adjusted(base, hue: hue, saturation: saturation, brightness: brightness, maxLuminance: 0.5)
        let darkAccent = Self.adjusted(base, hue: hue, saturation: saturation, brightness: brightness, minLuminance: 0.12)
        accent = Color(light: lightAccent, dark: darkAccent)
        onAccent = Color(light: Self.readable(on: lightAccent), dark: Self.readable(on: darkAccent))
    }

    private static func adjusted(_ color: UIColor, hue: CGFloat, saturation: CGFloat, brightness: CGFloat,
                                 minLuminance: CGFloat = 0, maxLuminance: CGFloat = 1) -> UIColor {
        var b = brightness
        var result = color
        for _ in 0..<12 {
            let l = luminance(result)
            if l > maxLuminance { b *= 0.92 } else if l < minLuminance { b = min(1, b + 0.08) } else { break }
            result = UIColor(hue: hue, saturation: saturation, brightness: b, alpha: 1)
        }
        return result
    }

    /// Near-black or white, whichever reads better on `color`.
    private static func readable(on color: UIColor) -> UIColor {
        luminance(color) > 0.36 ? UIColor(hex: 0x0B0B0C) : .white
    }

    /// Relative luminance (WCAG).
    static func luminance(_ color: UIColor) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        func linear(_ c: CGFloat) -> CGFloat {
            let c = min(1, max(0, c))
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }
}

extension Color {
    /// A color that switches with light and dark mode.
    init(light: UIColor, dark: UIColor) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    /// This color as 0xRRGGBB.
    var hexValue: UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ c: CGFloat) -> UInt32 { UInt32((min(1, max(0, c)) * 255).rounded()) }
        return byte(r) << 16 | byte(g) << 8 | byte(b)
    }
}

/// Mono, the presets, and a color well for any other color, as a row of swatches.
struct ThemeColorPicker: View {
    @Bindable var store = ThemeStore.shared

    var body: some View {
        HStack(spacing: 0) {
            swatch(nil)
            ForEach(ThemeStore.presets, id: \.self) { color in
                Spacer(minLength: 4)
                swatch(color)
            }
            Spacer(minLength: 4)
            customWell
        }
        .sensoryFeedback(.selection, trigger: store.tint)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Theme color")
    }

    private func swatch(_ color: UInt32?) -> some View {
        let isOn = store.tint == color
        return Button {
            withAnimation(Theme.settle) { store.tint = color }
        } label: {
            Group {
                if let color {
                    Circle().fill(Color(hex: color))
                } else {
                    // Mono: half black, half white.
                    Circle().fill(Color(hex: 0x111113))
                        .overlay {
                            Circle().fill(.white).mask(alignment: .leading) {
                                Rectangle().frame(width: 15)
                            }
                        }
                        .overlay(Circle().strokeBorder(Theme.lineStrong, lineWidth: 1))
                }
            }
            .frame(width: 30, height: 30)
            .padding(4)
            .overlay(Circle().strokeBorder(isOn ? Theme.text : .clear, lineWidth: 2))
            .frame(width: 42, height: 42)
            .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.9))
        .accessibilityLabel(color.map(Self.name) ?? "Mono")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// The system color well: picks any color. Ringed when the theme color isn't a preset.
    private var customWell: some View {
        let isOn = store.tint.map { !ThemeStore.presets.contains($0) } ?? false
        return ColorPicker("Custom color", selection: Binding(
            get: { Color(hex: store.tint ?? 0x0A84FF) },
            set: { store.tint = $0.hexValue }
        ), supportsOpacity: false)
        .labelsHidden()
        .frame(width: 30, height: 30)
        .padding(4)
        .overlay(Circle().strokeBorder(isOn ? Theme.text : .clear, lineWidth: 2))
        .frame(width: 42, height: 42)
    }

    private static func name(_ color: UInt32) -> String {
        switch color {
        case 0x0A84FF: return "Blue"
        case 0xBF5AF2: return "Purple"
        case 0xFF375F: return "Pink"
        case 0xFF9F0A: return "Orange"
        case 0x30D158: return "Green"
        default: return "Custom"
        }
    }
}
