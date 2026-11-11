import Foundation

/// Well-known apps and the IDs Samsung gives them. Newer Samsung TVs no longer answer the
/// "list installed apps" request, so the app checks these one by one instead.
///
/// IDs from samsung-tv-ws-api's APPLICATIONS.md. They can differ by TV year, so each app lists
/// every known ID, newest first (2020 and later sets use the newer ones). `aliases` are the LG IDs
/// the app's default Favorites use, so a pin made before this existed still opens the right app.
public struct SamsungApp: Sendable, Equatable {
    public let name: String
    public let ids: [String]
    public let aliases: [String]

    init(_ name: String, _ ids: [String], aliases: [String] = []) {
        self.name = name
        self.ids = ids
        self.aliases = aliases
    }

    public static let catalog: [SamsungApp] = [
        SamsungApp("Netflix", ["3201907018807", "11101200001"], aliases: ["netflix"]),
        SamsungApp("YouTube", ["111299001912"], aliases: ["youtube.leanback.v4"]),
        SamsungApp("Prime Video", ["3201910019365", "3201512006785"], aliases: ["amazon"]),
        SamsungApp("Disney+", ["3202204027038", "3202009021709", "3201901017640"]),
        SamsungApp("HBO Max", ["3202301029760", "3201601007230"], aliases: ["com.hbo.hbomax"]),
        SamsungApp("Apple TV", ["3201807016597"], aliases: ["com.apple.appletv"]),
        SamsungApp("Spotify", ["3201606009684"], aliases: ["spotify-beehive"]),
        SamsungApp("Paramount+", ["3202110025305", "3201710014981"], aliases: ["com.cbs-ent.paramountplus"]),
        SamsungApp("Hulu", ["3201601007625"]),
        SamsungApp("Peacock", ["3202006020991"]),
        SamsungApp("Plex", ["3201512006963"]),
        SamsungApp("Tubi", ["3201504001965"]),
        SamsungApp("Pluto TV", ["3201808016802"]),
        SamsungApp("Twitch", ["3202203026841"]),
        SamsungApp("Internet", ["3202010022079", "3201907018784", "org.tizen.browser"]),
    ]

    /// The catalog entry an ID belongs to, whether it's one of Samsung's IDs or an LG alias.
    public static func entry(for id: String) -> SamsungApp? {
        catalog.first { $0.ids.contains(id) || $0.aliases.contains(id) }
    }

    /// The IDs to try for `id`: the ID itself first if it's a Samsung one, then the entry's others.
    static func candidates(for id: String) -> [String] {
        guard let entry = entry(for: id) else { return [id] }
        return entry.ids.contains(id) ? [id] + entry.ids.filter { $0 != id } : entry.ids
    }
}

/// What a Samsung TV says about one app at `http://<host>:8001/api/v2/applications/<id>`.
public enum SamsungAppStatus: Sendable, Equatable {
    case notInstalled
    case installed(running: Bool)
    /// The TV didn't answer usefully, so we can't tell.
    case unknown

    /// The TV answers 200 with the app's details when it's installed, 404 when it isn't.
    static func parse(statusCode: Int, body: Data) -> SamsungAppStatus {
        if statusCode == 404 { return .notInstalled }
        guard statusCode == 200, let json = try? JSONDecoder().decode(JSONValue.self, from: body),
              json["id"]?.stringValue != nil
        else { return .unknown }
        return .installed(running: json["running"]?.boolValue ?? false)
    }
}

/// Samsung's local HTTP API for apps. No pairing needed. Not every set still honours it,
/// so callers treat `.unknown` as "can't tell" rather than "not installed".
enum SamsungREST {
    static func status(host: String, appID: String, timeout: TimeInterval = 2) async -> SamsungAppStatus {
        guard let (code, body) = await call("GET", host: host, appID: appID, timeout: timeout) else { return .unknown }
        return SamsungAppStatus.parse(statusCode: code, body: body)
    }

    /// Asks the TV to open the app. Returns false if the TV refused or didn't answer.
    @discardableResult
    static func launch(host: String, appID: String) async -> Bool {
        guard let (code, _) = await call("POST", host: host, appID: appID, timeout: 3) else { return false }
        return code == 200
    }

    private static func call(_ method: String, host: String, appID: String, timeout: TimeInterval) async -> (Int, Data)? {
        guard let id = appID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "http://\(host):8001/api/v2/applications/\(id)")
        else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        guard let (data, response) = try? await URLSession(configuration: configuration).data(for: request),
              let http = response as? HTTPURLResponse
        else { return nil }
        return (http.statusCode, data)
    }
}
