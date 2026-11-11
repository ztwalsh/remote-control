import Foundation

/// A Vizio SmartCast TV's local HTTPS API (self-signed certificate, pinned like LG's).
///
/// Pairing is by PIN: the TV shows four digits and the person types them into the app, which
/// trades them for an auth token sent with every later request. Newer firmware listens on 7345,
/// older on 9000. There's no socket, so "connected" means the TV answered and is on.
///
/// Paths and key codes follow pyvizio. Not yet verified against hardware.
public actor VizioClient: TVSession {
    public nonisolated let host: String
    public nonisolated let states: AsyncStream<ConnectionState>

    static let ports = [7345, 9000]
    static let deviceID = "remote-ios"
    static let deviceName = "Remote"

    private let trust: CertificateTrust
    private nonisolated let session: URLSession
    private var port = ports[0]
    private var token: String?
    private var pinProvider: (@Sendable () async -> String?)?
    private let stateContinuation: AsyncStream<ConnectionState>.Continuation

    public init(host: String, pinnedFingerprint: String? = nil) {
        self.host = host
        trust = CertificateTrust(pinnedFingerprint: pinnedFingerprint)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        session = URLSession(configuration: configuration, delegate: trust, delegateQueue: nil)
        let (stream, continuation) = AsyncStream<ConnectionState>.makeStream()
        states = stream
        stateContinuation = continuation
    }

    public var certificateFingerprint: String? { trust.fingerprint }

    /// Asked for the PIN the TV shows while pairing. Returning nil cancels.
    public func setPINProvider(_ provider: @escaping @Sendable () async -> String?) {
        pinProvider = provider
    }

    /// With a token, checks the TV answers and is on. Without one, pairs: the TV shows a PIN,
    /// the PIN provider supplies it, and the TV's auth token comes back.
    public func connect(clientKey: String?) async throws -> String {
        stateContinuation.yield(.connecting)
        do {
            let key = try await (clientKey?.isEmpty == false ? resume(clientKey!) : pair())
            stateContinuation.yield(.connected)
            return key
        } catch {
            stateContinuation.yield(.disconnected)
            throw error
        }
    }

    public func disconnect() {
        stateContinuation.yield(.disconnected)
    }

    private func resume(_ key: String) async throws -> String {
        token = key
        try await findPort()
        guard try await isOn() else { throw TVError.notConnected }
        return key
    }

    private func pair() async throws -> String {
        token = nil
        try await findPort()
        let start = try await call("PUT", "/pairing/start", [
            "DEVICE_ID": .string(Self.deviceID), "DEVICE_NAME": .string(Self.deviceName),
        ])
        guard let request = start["item"]?["pairing_req_token"]?.intValue else { throw TVError.invalidResponse }
        let challenge = start["item"]?["challenge_type"]?.intValue ?? 1
        stateContinuation.yield(.awaitingPairing)

        guard let pin = await pinProvider?(), !pin.isEmpty else {
            // pyvizio's cancel: the TV wants the pairing request back, with a placeholder PIN.
            _ = try? await call("PUT", "/pairing/cancel", [
                "DEVICE_ID": .string(Self.deviceID),
                "CHALLENGE_TYPE": .number(Double(challenge)),
                "PAIRING_REQ_TOKEN": .number(Double(request)),
                "RESPONSE_VALUE": "1111",
            ])
            throw TVError.pairingRejected
        }
        let reply: JSONValue
        do {
            reply = try await call("PUT", "/pairing/pair", [
                "DEVICE_ID": .string(Self.deviceID),
                "CHALLENGE_TYPE": .number(Double(challenge)),
                "PAIRING_REQ_TOKEN": .number(Double(request)),
                "RESPONSE_VALUE": .string(pin),
            ])
        } catch TVError.server {
            throw TVError.pairingRejected
        }
        guard let key = reply["item"]?["auth_token"]?.stringValue else { throw TVError.pairingRejected }
        token = key
        return key
    }

    /// Uses whichever port answers.
    private func findPort() async throws {
        for candidate in [port] + Self.ports.filter({ $0 != port }) {
            if (try? await raw("GET", "/state/device/deviceinfo", port: candidate)) != nil {
                port = candidate
                return
            }
        }
        throw TVError.notConnected
    }

    /// True if a Vizio TV answers at `host`, for telling brands apart when an address is typed.
    public static func probe(host: String) async -> Bool {
        let client = VizioClient(host: host)
        return (try? await client.findPort()) != nil
    }

    // MARK: - Commands

    public func isOn() async throws -> Bool {
        let reply = try await call("GET", "/state/device/power_mode")
        return reply["items"]?.arrayValue?.first?["value"]?.intValue == 1
    }

    /// The TV's network (MAC) addresses for Wake-on-LAN, read while it's on. Vizio doesn't document
    /// which field holds them, so this collects anything shaped like a MAC address from the device
    /// info and the network information page.
    public func macAddresses() async -> [String] {
        var found: [String] = []
        for path in ["/state/device/deviceinfo", "/menu_native/dynamic/tv_settings/system/system_information/network_information"] {
            guard let reply = try? await call("GET", path) else { continue }
            for mac in Self.macAddresses(in: reply) where !found.contains(mac) { found.append(mac) }
        }
        return found
    }

    /// Every MAC-shaped string in a reply ("a0:b1:c2:d3:e4:f5" or with dashes), lowercased,
    /// skipping all-zero and broadcast placeholders.
    static func macAddresses(in json: JSONValue) -> [String] {
        switch json {
        case .string(let text):
            let parts = text.trimmingCharacters(in: .whitespaces).split(whereSeparator: { $0 == ":" || $0 == "-" })
            guard parts.count == 6, parts.allSatisfy({ $0.count == 2 && $0.allSatisfy(\.isHexDigit) }) else { return [] }
            let mac = parts.joined(separator: ":").lowercased()
            return ["00:00:00:00:00:00", "ff:ff:ff:ff:ff:ff"].contains(mac) ? [] : [mac]
        case .array(let items):
            return items.flatMap(macAddresses(in:))
        case .object(let object):
            return object.keys.sorted().flatMap { macAddresses(in: object[$0]!) }
        default:
            return []
        }
    }

    public func key(_ code: VizioKey) async throws {
        _ = try await call("PUT", "/key_command/", [
            "KEYLIST": .array([.object([
                "CODESET": .number(Double(code.codeset)),
                "CODE": .number(Double(code.code)),
                "ACTION": "KEYPRESS",
            ])]),
        ])
    }

    /// A setting's current value and its `hashval`, which the TV wants back when changing it.
    public func setting(_ path: String) async throws -> (value: JSONValue, hash: Int) {
        let reply = try await call("GET", "/menu_native/dynamic/tv_settings/\(path)")
        guard let item = reply["items"]?.arrayValue?.first, let hash = item["hashval"]?.intValue else {
            throw TVError.invalidResponse
        }
        return (item["value"] ?? .null, hash)
    }

    public func changeSetting(_ path: String, to value: JSONValue, hash: Int) async throws {
        _ = try await call("PUT", "/menu_native/dynamic/tv_settings/\(path)", [
            "REQUEST": "MODIFY", "HASHVAL": .number(Double(hash)), "VALUE": value,
        ])
    }

    /// The TV's inputs as `(name, label)`: "HDMI-1" and whatever it's been named, such as "Xbox".
    public func inputs() async throws -> [(name: String, label: String)] {
        let reply = try await call("GET", "/menu_native/dynamic/tv_settings/devices/name_input")
        return (reply["items"]?.arrayValue ?? []).compactMap { item in
            guard item["cname"]?.stringValue != "current_input", let name = item["name"]?.stringValue else { return nil }
            let label = item["value"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 } ?? name
            return (name, label)
        }
    }

    public func currentInput() async throws -> String? {
        try await setting("devices/current_input").value.stringValue
    }

    public func setInput(_ name: String) async throws {
        let current = try await setting("devices/current_input")
        try await changeSetting("devices/current_input", to: .string(name), hash: current.hash)
    }

    /// The app on screen as `(namespace, appID)`, or nil when none is.
    public func currentApp() async throws -> (namespace: Int, appID: String)? {
        let value = try await call("GET", "/app/current")["item"]?["value"]
        guard let appID = value?["app_id"]?.stringValue, let namespace = value?["name_space"]?.intValue else { return nil }
        return (namespace, appID)
    }

    public func launch(namespace: Int, appID: String, message: String?) async throws {
        _ = try await call("PUT", "/app/launch", [
            "VALUE": .object([
                "APP_ID": .string(appID),
                "NAME_SPACE": .number(Double(namespace)),
                "MESSAGE": message.map(JSONValue.string) ?? .null,
            ]),
        ])
    }

    // MARK: - HTTP

    /// Sends a request and checks the TV's `STATUS.RESULT`. Keys come back lowercased.
    private func call(_ method: String, _ path: String, _ body: [String: JSONValue]? = nil) async throws -> JSONValue {
        let reply = try await raw(method, path, port: port, body: body)
        let result = reply["status"]?["result"]?.stringValue?.lowercased()
        guard result == "success" else {
            throw TVError.server(reply["status"]?["detail"]?.stringValue ?? result ?? "Request failed")
        }
        return reply
    }

    private func raw(_ method: String, _ path: String, port: Int, body: [String: JSONValue]? = nil) async throws -> JSONValue {
        guard let url = URL(string: "https://\(host):\(port)\(path)") else { throw TVError.notConnected }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let token { request.setValue(token, forHTTPHeaderField: "AUTH") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(JSONValue.object(body))
        }
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode(JSONValue.self, from: data).lowercasedKeys()
    }
}

/// A Vizio remote key as (codeset, code), from pyvizio's table.
public struct VizioKey: Sendable, Equatable {
    public let codeset: Int
    public let code: Int

    public static let volumeDown = VizioKey(codeset: 5, code: 0)
    public static let volumeUp = VizioKey(codeset: 5, code: 1)
    public static let muteOff = VizioKey(codeset: 5, code: 2)
    public static let muteOn = VizioKey(codeset: 5, code: 3)
    public static let powerOff = VizioKey(codeset: 11, code: 0)
    public static let powerOn = VizioKey(codeset: 11, code: 1)
    public static let up = VizioKey(codeset: 3, code: 8)
    public static let down = VizioKey(codeset: 3, code: 0)
    public static let left = VizioKey(codeset: 3, code: 1)
    public static let right = VizioKey(codeset: 3, code: 7)
    public static let ok = VizioKey(codeset: 3, code: 2)
    public static let back = VizioKey(codeset: 4, code: 0)
    public static let home = VizioKey(codeset: 4, code: 15)
}

extension JSONValue {
    /// Vizio's field names vary in case between firmware versions; lowercase them all.
    func lowercasedKeys() -> JSONValue {
        switch self {
        case .object(let object):
            return .object(Dictionary(object.map { ($0.key.lowercased(), $0.value.lowercasedKeys()) }, uniquingKeysWith: { first, _ in first }))
        case .array(let items):
            return .array(items.map { $0.lowercasedKeys() })
        default:
            return self
        }
    }
}
