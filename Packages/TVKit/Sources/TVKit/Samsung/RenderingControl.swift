import Foundation

/// The UPnP RenderingControl service Samsung TVs run on port 9197. Its remote socket can only step
/// the volume, but this reads and sets the exact level and mute. Some models don't offer it;
/// `SamsungTV` then falls back to volume keys.
struct RenderingControl: Sendable {
    let url: URL
    private let session: URLSession

    init?(host: String) {
        guard let url = URL(string: "http://\(host):9197/upnp/control/RenderingControl1") else { return nil }
        self.url = url
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 2
        session = URLSession(configuration: configuration)
    }

    func volume() async throws -> Int {
        let reply = try await call("GetVolume", ["InstanceID": "0", "Channel": "Master"])
        guard let level = Self.value("CurrentVolume", in: reply).flatMap(Int.init) else { throw TVError.invalidResponse }
        return level
    }

    func setVolume(_ level: Int) async throws {
        _ = try await call("SetVolume", ["InstanceID": "0", "Channel": "Master", "DesiredVolume": String(level)])
    }

    func isMuted() async throws -> Bool {
        let reply = try await call("GetMute", ["InstanceID": "0", "Channel": "Master"])
        guard let value = Self.value("CurrentMute", in: reply) else { throw TVError.invalidResponse }
        return value == "1" || value.lowercased() == "true"
    }

    func setMute(_ muted: Bool) async throws {
        _ = try await call("SetMute", ["InstanceID": "0", "Channel": "Master", "DesiredMute": muted ? "1" : "0"])
    }

    static let service = "urn:schemas-upnp-org:service:RenderingControl:1"

    static func envelope(_ action: String, _ arguments: KeyValuePairs<String, String>) -> String {
        let body = arguments.map { "<\($0.key)>\($0.value)</\($0.key)>" }.joined()
        return """
        <?xml version="1.0" encoding="utf-8"?>\
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">\
        <s:Body><u:\(action) xmlns:u="\(service)">\(body)</u:\(action)></s:Body></s:Envelope>
        """
    }

    static func value(_ tag: String, in xml: String) -> String? {
        guard let start = xml.range(of: "<\(tag)>"), let end = xml.range(of: "</\(tag)>", range: start.upperBound..<xml.endIndex) else {
            return nil
        }
        return String(xml[start.upperBound..<end.lowerBound])
    }

    private func call(_ action: String, _ arguments: KeyValuePairs<String, String>) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"\(Self.service)#\(action)\"", forHTTPHeaderField: "SOAPACTION")
        request.httpBody = Data(Self.envelope(action, arguments).utf8)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw TVError.unsupported("RenderingControl \(action)")
        }
        return String(decoding: data, as: UTF8.self)
    }
}
