import Foundation

public enum TVError: Error, Equatable, Sendable {
    case notConnected
    case pairingRejected
    case timeout
    case invalidResponse
    case invalidMACAddress
    case missingMACAddress
    case unsupported(String)
    case server(String)
}

/// Volume as the TV reports it. `soundOutput` is only included by newer webOS versions.
public struct VolumeStatus: Sendable, Equatable {
    public var level: Int
    public var muted: Bool
    public var soundOutput: SoundOutput?

    public init(level: Int, muted: Bool, soundOutput: SoundOutput? = nil) {
        self.level = level
        self.muted = muted
        self.soundOutput = soundOutput
    }

    /// Reads both shapes in the wild:
    /// older webOS `{ "volume": 12, "muted": false }` and
    /// newer webOS `{ "volumeStatus": { "volume": 12, "muteStatus": false, "soundOutput": "tv_speaker" } }`.
    public static func parse(_ payload: JSONValue) -> VolumeStatus? {
        if let status = payload["volumeStatus"], let level = status["volume"]?.intValue {
            return VolumeStatus(
                level: level,
                muted: status["muteStatus"]?.boolValue ?? false,
                soundOutput: status["soundOutput"]?.stringValue.map(SoundOutput.init(rawValue:))
            )
        }
        if let level = payload["volume"]?.intValue {
            return VolumeStatus(level: level, muted: payload["muted"]?.boolValue ?? false)
        }
        return nil
    }
}

/// Where the TV's audio goes. The raw names vary by model year, so unknown ones are kept as `.other`.
public enum SoundOutput: Sendable, Hashable {
    case tvSpeaker
    case hdmiARC
    case optical
    case bluetooth
    case headphones
    case other(String)

    public init(rawValue: String) {
        switch rawValue {
        case "tv_speaker": self = .tvSpeaker
        case "external_arc": self = .hdmiARC
        case "external_optical": self = .optical
        case "bt_soundbar": self = .bluetooth
        case "headphone": self = .headphones
        default: self = .other(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .tvSpeaker: return "tv_speaker"
        case .hdmiARC: return "external_arc"
        case .optical: return "external_optical"
        case .bluetooth: return "bt_soundbar"
        case .headphones: return "headphone"
        case .other(let raw): return raw
        }
    }
}

/// An app installed on the TV, with the icon the TV serves for it.
public struct LaunchPoint: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let iconURL: URL?

    public init(id: String, title: String, iconURL: URL?) {
        self.id = id
        self.title = title
        self.iconURL = iconURL
    }

    /// HDMI ports, the antenna and other sources, which the TV lists alongside apps.
    /// Matched by app ID, since webOS gives them no separate type in this list.
    public var isInput: Bool {
        let id = id.lowercased()
        return Self.inputPrefixes.contains { id.hasPrefix($0) } || Self.inputIDs.contains(id)
    }

    static let inputPrefixes = ["com.webos.app.hdmi", "com.webos.app.externalinput", "vizio.input."]
    static let inputIDs: Set<String> = ["com.webos.app.livetv", "com.webos.app.tvsimpleviewer"]

    public static func parseList(_ payload: JSONValue) -> [LaunchPoint] {
        (payload["launchPoints"]?.arrayValue ?? []).compactMap { item in
            guard let id = item["id"]?.stringValue else { return nil }
            let icon = (item["largeIcon"]?.stringValue ?? item["icon"]?.stringValue).flatMap(URL.init(string:))
            return LaunchPoint(id: id, title: item["title"]?.stringValue ?? id, iconURL: icon)
        }
    }
}

/// Changes pushed by the TV while connected.
public enum TVEvent: Sendable, Equatable {
    case volume(VolumeStatus)
    case soundOutput(SoundOutput)
    case foregroundApp(String?)
    /// The TV opened (true) or closed (false) its on-screen keyboard for a text field.
    case keyboard(Bool)
    /// Whether what's on screen is paused (true) or playing (false). Only LG reports it, and only
    /// for apps that play through the TV's own media player.
    case paused(Bool)
    case disconnected
}
