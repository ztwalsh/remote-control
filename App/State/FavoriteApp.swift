import SwiftUI
import TVKit

/// An app on the Favorites grid.
///
/// The webOS app IDs below still need checking against `listLaunchPoints` on a real TV.
/// Once paired, the app should use the TV's own icons (`LaunchPoint.iconURL`) instead of bundled logos.
struct FavoriteApp: Identifiable, Hashable {
    let id: String
    let name: String
    /// Asset catalog image: a single-color logo, tinted with `glyph`.
    let logo: String
    let tile: Color
    let glyph: Color
    let logoSize: CGFloat

    static let defaults: [FavoriteApp] = [
        FavoriteApp(id: "netflix", name: "Netflix", logo: "logo-netflix",
                    tile: .black, glyph: Color(hex: 0xE50914), logoSize: 30),
        FavoriteApp(id: "youtube.leanback.v4", name: "YouTube", logo: "logo-youtube",
                    tile: .white, glyph: Color(hex: 0xFF0000), logoSize: 36),
        FavoriteApp(id: "amazon", name: "Prime Video", logo: "logo-primevideo",
                    tile: Color(hex: 0x00A8E1), glyph: .white, logoSize: 44),
        FavoriteApp(id: "com.hbo.hbomax", name: "HBO Max", logo: "logo-hbo",
                    tile: .black, glyph: .white, logoSize: 46),
        FavoriteApp(id: "com.apple.appletv", name: "Apple TV", logo: "logo-appletv",
                    tile: .black, glyph: .white, logoSize: 38),
        FavoriteApp(id: "spotify-beehive", name: "Spotify", logo: "logo-spotify",
                    tile: .black, glyph: Color(hex: 0x1ED760), logoSize: 36),
        FavoriteApp(id: "com.cbs-ent.paramountplus", name: "Paramount+", logo: "logo-paramountplus",
                    tile: Color(hex: 0x0064FF), glyph: .white, logoSize: 38),
        FavoriteApp(id: "com.webos.app.lgchannels", name: "LG Channels", logo: "logo-lg",
                    tile: Color(hex: 0xA50034), glyph: .white, logoSize: 34),
    ]
}

extension SoundOutput {
    var displayName: String {
        switch self {
        case .tvSpeaker: return "TV speakers"
        case .hdmiARC: return "Soundbar"
        case .optical: return "Receiver"
        case .bluetooth: return "Headphones"
        case .headphones: return "Wired headphones"
        case .other(let raw): return raw
        }
    }

    var systemImage: String {
        switch self {
        case .tvSpeaker: return "tv"
        case .hdmiARC: return "hifispeaker"
        case .optical: return "hifireceiver"
        case .bluetooth, .headphones: return "headphones"
        case .other: return "speaker.wave.2"
        }
    }

    /// The outputs offered in Sound out. Once paired, this should be the list the TV reports.
    static let choices: [SoundOutput] = [.tvSpeaker, .hdmiARC, .bluetooth, .optical]
}
