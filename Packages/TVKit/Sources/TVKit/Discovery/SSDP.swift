import Foundation
import Network

/// Finding LG TVs on the local network with SSDP.
public enum SSDP {
    public static let searchTarget = "urn:lge-com:service:webos-second-screen:1"
    static let multicastHost = "239.255.255.250"
    static let multicastPort: UInt16 = 1900

    public static var searchRequest: Data {
        Data((
            "M-SEARCH * HTTP/1.1\r\n" +
            "HOST: \(multicastHost):\(multicastPort)\r\n" +
            "MAN: \"ssdp:discover\"\r\n" +
            "MX: 2\r\n" +
            "ST: \(searchTarget)\r\n\r\n"
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
    public static func parseDescription(_ xml: String) -> (name: String?, model: String?) {
        func tag(_ name: String) -> String? {
            guard let start = xml.range(of: "<\(name)>"), let end = xml.range(of: "</\(name)>", range: start.upperBound..<xml.endIndex) else {
                return nil
            }
            return String(xml[start.upperBound..<end.lowerBound])
        }
        return (tag("friendlyName"), tag("modelName"))
    }
}

/// A TV found on the network.
public struct DiscoveredTV: Sendable, Equatable, Identifiable {
    public var id: String { usn ?? host }
    public let host: String
    public let usn: String?
    public var name: String?
    public var model: String?
}

/// Sends an M-SEARCH and collects replies for a few seconds.
///
/// Needs the multicast entitlement on a device (the simulator doesn't). Not yet verified on hardware.
public final class SSDPBrowser: @unchecked Sendable {
    public init() {}

    public func search(for duration: Duration = .seconds(3)) async throws -> [DiscoveredTV] {
        guard let port = NWEndpoint.Port(rawValue: SSDP.multicastPort) else { return [] }
        let group = try NWMulticastGroup(for: [.hostPort(host: NWEndpoint.Host(SSDP.multicastHost), port: port)])
        let connection = NWConnectionGroup(with: group, using: .udp)
        let found = FoundTVs()

        connection.setReceiveHandler(maximumMessageSize: 16_384, rejectOversizedMessages: true) { message, content, _ in
            guard let content, let text = String(data: content, encoding: .utf8), let response = SSDP.parse(text),
                  response.searchTarget == SSDP.searchTarget,
                  case .hostPort(let host, _)? = message.remoteEndpoint
            else { return }
            // Drop any interface suffix such as "%en0".
            let address = String("\(host)".split(separator: "%").first ?? "")
            found.add(DiscoveredTV(host: address, usn: response.usn), location: response.location)
        }
        connection.stateUpdateHandler = { state in
            if case .ready = state {
                connection.send(content: SSDP.searchRequest) { _ in }
            }
        }
        connection.start(queue: .global(qos: .userInitiated))
        try await Task.sleep(for: duration)
        connection.cancel()

        var results: [DiscoveredTV] = []
        for (tv, location) in found.all {
            var tv = tv
            if let location, let response = try? await URLSession.shared.data(from: location) {
                let description = SSDP.parseDescription(String(decoding: response.0, as: UTF8.self))
                tv.name = description.name
                tv.model = description.model
            }
            results.append(tv)
        }
        return results
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
