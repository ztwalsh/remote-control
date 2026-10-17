import Foundation

/// A message to the TV over SSAP (LG's "second screen" WebSocket protocol).
struct SSAPOutgoing: Encodable, Equatable {
    let type: String
    let id: String
    var uri: String?
    var payload: JSONValue?
}

/// A message from the TV. `id` echoes the request it answers; subscriptions keep reusing theirs.
struct SSAPIncoming: Decodable, Equatable {
    let type: String
    let id: String?
    let payload: JSONValue?
    let error: String?
}

/// SSAP endpoints this app uses. Rows marked "verify" still need checking on a real TV (plan, phase 0).
public enum SSAPURI {
    public static let getVolume = "ssap://audio/getVolume"
    public static let setVolume = "ssap://audio/setVolume"
    public static let setMute = "ssap://audio/setMute"
    public static let volumeUp = "ssap://audio/volumeUp"
    public static let volumeDown = "ssap://audio/volumeDown"
    public static let turnOff = "ssap://system/turnOff"
    public static let systemInfo = "ssap://system/getSystemInfo"
    public static let launch = "ssap://system.launcher/launch"
    public static let listLaunchPoints = "ssap://com.webos.applicationManager/listLaunchPoints"
    public static let foregroundApp = "ssap://com.webos.applicationManager/getForegroundAppInfo"
    public static let getSoundOutput = "ssap://com.webos.service.apiadapter/audio/getSoundOutput"
    public static let changeSoundOutput = "ssap://com.webos.service.apiadapter/audio/changeSoundOutput"
    /// verify: used to read the MAC address for Wake-on-LAN.
    public static let connectionInfo = "ssap://com.webos.service.connectionmanager/getinfo"
}

/// The register payload. The TV shows an "Allow this device?" prompt the first time.
enum SSAPRegistration {
    static let messageID = "register_0"

    static let permissions: [String] = [
        "LAUNCH",
        "LAUNCH_WEBAPP",
        "APP_TO_APP",
        "CONTROL_AUDIO",
        "CONTROL_DISPLAY",
        "CONTROL_INPUT_MEDIA_PLAYBACK",
        "CONTROL_POWER",
        "CONTROL_TV_POWER",
        "CONTROL_TIMER_INFO",
        "READ_APP_STATUS",
        "READ_INSTALLED_APPS",
        "READ_NETWORK_STATE",
        "READ_POWER_STATE",
        "READ_RUNNING_APPS",
        "READ_SETTINGS",
        "READ_TV_CURRENT_TIME",
    ]

    static func payload(clientKey: String?) -> JSONValue {
        var payload: [String: JSONValue] = [
            "forcePairing": false,
            "pairingType": "PROMPT",
            "manifest": [
                "manifestVersion": 1,
                "appVersion": "1.0",
                "permissions": .array(permissions.map { .string($0) }),
            ],
        ]
        if let clientKey {
            payload["client-key"] = .string(clientKey)
        }
        return .object(payload)
    }
}
