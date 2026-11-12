import SwiftUI
import TVKit

/// An app pinned to a TV's Favorites grid. Kept with its name and icon address,
/// so the grid draws before the TV's app list has loaded.
struct PinnedApp: Codable, Hashable, Identifiable {
    let id: String
    var title: String
    var iconURL: URL?

    init(id: String, title: String, iconURL: URL?) {
        self.id = id
        self.title = title
        self.iconURL = iconURL
    }

    init(_ point: LaunchPoint) {
        self.init(id: point.id, title: point.title, iconURL: point.iconURL)
    }

    /// A bundled logo for a well-known app, drawn instead of the TV's icon.
    /// Matched by name too, since Samsung uses its own app IDs.
    var bundled: FavoriteApp? {
        FavoriteApp.defaults.first { $0.id == id } ?? FavoriteApp.defaults.first { $0.name.caseInsensitiveCompare(title) == .orderedSame }
    }

    /// The now-playing strip's color: the app's brand, or a neutral dark grey for others.
    var playerColor: Color {
        bundled?.player ?? Color(hex: 0x2C2C30)
    }
}

/// Each TV's pinned apps, in grid order, kept in UserDefaults by TV id.
/// A TV with no entry hasn't been set up yet; the app seeds it from `FavoriteApp.defaults`.
enum PinnedApps {
    private static let key = "pinnedApps"

    static func load() -> [String: [PinnedApp]] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: [PinnedApp]].self, from: data)) ?? [:]
    }

    static func save(_ pins: [String: [PinnedApp]]) {
        guard let data = try? JSONEncoder().encode(pins) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

/// A bundled logo for a well-known app, and the starting Favorites for a newly paired TV
/// (only the ones it actually has installed).
struct FavoriteApp: Identifiable, Hashable {
    let id: String
    let name: String
    /// Asset catalog image: a single-color logo, tinted with `glyph`.
    let logo: String
    let tile: Color
    let glyph: Color
    let logoSize: CGFloat
    /// The now-playing strip's background: a dark shade of the app's brand color.
    let player: Color

    static let defaults: [FavoriteApp] = [
        FavoriteApp(id: "netflix", name: "Netflix", logo: "logo-netflix",
                    tile: .black, glyph: Color(hex: 0xE50914), logoSize: 30,
                    player: Color(hex: 0x600408)),
        FavoriteApp(id: "youtube.leanback.v4", name: "YouTube", logo: "logo-youtube",
                    tile: .white, glyph: Color(hex: 0xFF0000), logoSize: 36,
                    player: Color(hex: 0x6B0000)),
        FavoriteApp(id: "amazon", name: "Prime Video", logo: "logo-primevideo",
                    tile: Color(hex: 0x00A8E1), glyph: .white, logoSize: 44,
                    player: Color(hex: 0x00475F)),
        FavoriteApp(id: "com.hbo.hbomax", name: "HBO Max", logo: "logo-hbo",
                    tile: .black, glyph: .white, logoSize: 46,
                    player: Color(hex: 0x2E1466)),
        FavoriteApp(id: "com.apple.appletv", name: "Apple TV", logo: "logo-appletv",
                    tile: .black, glyph: .white, logoSize: 38,
                    player: Color(hex: 0x1F1F22)),
        FavoriteApp(id: "spotify-beehive", name: "Spotify", logo: "logo-spotify",
                    tile: .black, glyph: Color(hex: 0x1ED760), logoSize: 36,
                    player: Color(hex: 0x0D5A28)),
        FavoriteApp(id: "com.cbs-ent.paramountplus", name: "Paramount+", logo: "logo-paramountplus",
                    tile: Color(hex: 0x0064FF), glyph: .white, logoSize: 38,
                    player: Color(hex: 0x002A6B)),
        FavoriteApp(id: "com.webos.app.lgchannels", name: "LG Channels", logo: "logo-lg",
                    tile: Color(hex: 0xA50034), glyph: .white, logoSize: 34,
                    player: Color(hex: 0x450016)),
    ]

    var pinned: PinnedApp { PinnedApp(id: id, title: name, iconURL: nil) }
}

extension SoundOutput {
    var displayName: String {
        switch self {
        case .tvSpeaker: return "TV speakers"
        case .hdmiARC: return "Soundbar"
        case .optical: return "Receiver"
        case .bluetooth: return "Headphones"
        case .headphones: return "Wired headphones"
        case .other(let raw):
            switch raw {
            case "external_speaker": return "External speaker"
            case "lineout": return "Line out"
            case "tv_external_speaker": return "TV + soundbar"
            case "tv_speaker_headphone": return "TV + headphones"
            default: return raw.replacingOccurrences(of: "_", with: " ").capitalized
            }
        }
    }

    var icon: Icon {
        switch self {
        case .tvSpeaker: return .tv
        case .hdmiARC: return .speaker
        case .optical: return .receiver
        case .bluetooth, .headphones: return .headphones
        case .other: return .volume
        }
    }

    /// Common outputs, offered under "Try another output" until a TV has used them.
    /// webOS can't list a TV's outputs, so the app learns them (see `RemoteStore.availableOutputs`).
    static let choices: [SoundOutput] = [.tvSpeaker, .hdmiARC, .bluetooth, .optical, .headphones]
}

/// The sound outputs one TV has used (raw webOS names, in order first seen) and the ones it refused.
struct OutputMemory: Codable, Equatable {
    var seen: [String] = []
    var refused: [String] = []

    private static let key = "soundOutputs"

    static func load() -> [String: OutputMemory] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: OutputMemory].self, from: data)) ?? [:]
    }

    static func save(_ memory: [String: OutputMemory]) {
        guard let data = try? JSONEncoder().encode(memory) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
