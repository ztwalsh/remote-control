import SwiftUI

/// The app's icons, from Central Icons (round, 2px radius, 2px stroke), stored as vector PDFs
/// in Assets.xcassets/Icons and drawn as templates so they take the surrounding color.
///
/// Central has no power, media or keyboard icons, so those are SF Symbols (`systemName`).
enum Icon: String {
    case tv, edit, back, close, pin, pinFill = "pin-fill", unpin, search, check, trash, plus, minus, moon, home
    case sun, system, speaker, receiver, headphones, volume, volumeOff = "volume-off", touch, refresh
    case chevronDown = "chevron-down", arrowUp = "arrow-up", arrowDown = "arrow-down"
    case arrowLeft = "arrow-left", arrowRight = "arrow-right"
    case power, play, pause, rewind, fastForward = "fast-forward", keyboard

    /// The asset name, for places that need one (menus, labels).
    var assetName: String { "icon-\(rawValue)" }

    /// The SF Symbol drawn for icons Central doesn't have.
    var systemName: String? {
        switch self {
        case .power: return "power"
        case .play: return "play.fill"
        case .pause: return "pause.fill"
        case .rewind: return "backward.fill"
        case .fastForward: return "forward.fill"
        case .keyboard: return "keyboard"
        default: return nil
        }
    }
}

/// Draws an icon at a fixed size. The size is the icon's full 24-point grid, so 22 here matches
/// the visual weight of a 17-point SF Symbol.
struct IconView: View {
    let icon: Icon
    var size: CGFloat = 22

    init(_ icon: Icon, size: CGFloat = 22) {
        self.icon = icon
        self.size = size
    }

    var body: some View {
        if let symbol = icon.systemName {
            Image(systemName: symbol)
                .font(.system(size: size * 0.78, weight: .semibold))
                .frame(width: size, height: size)
        } else {
            Image(icon.assetName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        }
    }
}

/// A text label with an icon, sized to sit beside 15–17-point text.
struct IconLabel: View {
    let title: String
    let icon: Icon
    var size: CGFloat = 18

    var body: some View {
        HStack(spacing: 6) {
            IconView(icon, size: size)
            Text(title)
        }
    }
}
