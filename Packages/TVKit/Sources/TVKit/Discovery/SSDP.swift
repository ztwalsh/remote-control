import Foundation
import Network

/// Finding LG and Samsung TVs on the local network with SSDP.
public enum SSDP {
    public static let searchTarget = "urn:lge-com:service:webos-second-screen:1"
    public static let samsungSearchTarget = "urn:samsung.com:device:RemoteControlReceiver:1"
    /// Vizio answers the generic DIAL search, as do Chromecasts and others, so these replies are
    /// kept only when the device description says VIZIO.
    public static let dialSearchTarget = "urn:dial-multiscreen-org:service:dial:1"

    /// The brand a reply's search target belongs to, or nil for anything else.
    static func brand(for target: String?) -> TVBrand? {
        switch target {
        case searchTarget: return .lg
        case samsungSearchTarget: return .samsung
        case dialSearchTarget: return .vizio
        default: return nil
        }
    }
    static let multicastHost = "239.255.255.250"
    static let multicastPort: UInt16 = 1900

    public static var searchRequest: Data { searchRequest(for: searchTarget) }

    public static func searchRequest(for target: String) -> Data {
        Data((
            "M-SEARCH * HTTP/1.1\r\n" +
            "HOST: \(multicastHost):\(multicastPort)\r\n" +
            "MAN: \"ssdp:discover\"\r\n" +
            "MX: 2\r\n" +
            "ST: \(target)\r\n\r\n"
        ).utf8)
    }

    public struct Response: Sendable, Equatable {
        public let location: URL?
        public let searchTarget: String?
        public let usn: String?
        public let server: String?
    }

    /// Parses an SSDP reply. Header names are case-insensitive.
    public static func parse(_ text: String) -> Response? {
        let lines = text.components(separatedBy: "\r\n")
        guard let status = lines.first, status.uppercased().hasPrefix("HTTP/1.1 200") else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).uppercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }
        return Response(
            location: headers["LOCATION"].flatMap(URL.init(string:)),
            searchTarget: headers["ST"],
            usn: headers["USN"],
            server: headers["SERVER"]
        )
    }

    /// Pulls the friendly name ("Living room") and model out of the UPnP device description at `LOCATION`.
    public static func parseDescription(_ xml: String) -> (name: String?, model: String?, manufacturer: String?) {
        func tag(_ name: String) -> String? {
            guard let start = xml.range(of: "<\(name)>"), let end = xml.range(of: "</\(name)>", range: start.upperBound..<xml.endIndex) else {
                return nil
            }
            return String(xml[start.upperBound..<end.lowerBound])
        }
        return (tag("friendlyName"), tag("modelName"), tag("manufacturer"))
    }

    /// LG prefixes the name with "[LG]" and Samsung with "[TV]"; drop them so "[LG] webOS TV" reads as "webOS TV".
    public static func cleanName(_ name: String) -> String {
        var name = name.trimmingCharacters(in: .whitespaces)
        for prefix in ["[LG]", "[TV]"] where name.hasPrefix(prefix) {
            name = String(name.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        return name.isEmpty ? "TV" : name
    }
}

/// A TV found on the network.
public struct DiscoveredTV: Sendable, Equatable, Identifiable {
    public var id: String { usn ?? host }
    public let host: String
    public let usn: String?
    public var brand: TVBrand = .lg
    public var name: String?
    public var model: String?
}

/// Sends an M-SEARCH and collects replies for a few seconds.
///
/// Needs the multicast entitlement on a device (granted; see README). The first search on a phone
/// triggers the local network permission prompt, and finds nothing until the person allows it.
public final class SSDPBrowser: @unchecked Sendable {
    public init() {}

    public func search(for duration: Duration = .seconds(3)) async throws -> [DiscoveredTV] {
        guard let port = NWEndpoint.Port(rawValue: SSDP.multicastPort) else { return [] }
        let group = try NWMulticastGroup(for: [.hostPort(host: NWEndpoint.Host(SSDP.multicastHost), port: port)])
        let connection = NWConnectionGroup(with: group, using: .udp)
        defer { connection.cancel() }
        let found = FoundTVs()

        connection.setReceiveHandler(maximumMessageSize: 16_384, rejectOversizedMessages: true) { message, content, _ in
            guard let content, let text = String(data: content, encoding: .utf8), let response = SSDP.parse(text),
                  let brand = SSDP.brand(for: response.searchTarget),
                  case .hostPort(let host, _)? = message.remoteEndpoint
            else { return }
            // Drop any interface suffix such as "%en0".
            let address = String("\(host)".split(separator: "%").first ?? "")
            found.add(DiscoveredTV(host: address, usn: response.usn, brand: brand), location: response.location)
        }
        connection.stateUpdateHandler = { state in
            guard case .ready = state else { return }
            // UDP can drop the request; ask twice, for each brand.
            let requests = [SSDP.searchTarget, SSDP.samsungSearchTarget, SSDP.dialSearchTarget].map(SSDP.searchRequest(for:))
            for request in requests { connection.send(content: request) { _ in } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                for request in requests { connection.send(content: request) { _ in } }
            }
        }
        connection.start(queue: .global(qos: .userInitiated))
        try await Task.sleep(for: duration)
        connection.cancel()

        return await withTaskGroup(of: DiscoveredTV?.self) { tasks in
            for (tv, location) in found.all {
                tasks.addTask { await Self.describe(tv, location: location) }
            }
            var results: [DiscoveredTV] = []
            for await tv in tasks {
                if let tv { results.append(tv) }
            }
            return results.sorted { ($0.name ?? $0.host) < ($1.name ?? $1.host) }
        }
    }

    /// Adds the name and model from the TV's UPnP description, if it answers within two seconds.
    /// DIAL replies are dropped unless the description says VIZIO.
    private static func describe(_ tv: DiscoveredTV, location: URL?) async -> DiscoveredTV? {
        let isDIAL = tv.brand == .vizio
        guard let location else { return isDIAL ? nil : tv }
        var request = URLRequest(url: location)
        request.timeoutInterval = 2
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return isDIAL ? nil : tv }
        let description = SSDP.parseDescription(String(decoding: data, as: UTF8.self))
        if isDIAL, description.manufacturer?.uppercased().contains("VIZIO") != true { return nil }
        var tv = tv
        tv.name = description.name.map(SSDP.cleanName)
        tv.model = description.model
        return tv
    }
}

private final class FoundTVs: @unchecked Sendable {
    private let lock = NSLock()
    private var byID: [String: (DiscoveredTV, URL?)] = [:]

    func add(_ tv: DiscoveredTV, location: URL?) {
        lock.lock()
        byID[tv.id] = (tv, location)
        lock.unlock()
    }

    var all: [(DiscoveredTV, URL?)] {
        lock.lock()
        defer { lock.unlock() }
        return Array(byID.values)
    }
}
