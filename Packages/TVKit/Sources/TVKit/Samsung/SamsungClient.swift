import Foundation

/// One connection to a Samsung Smart TV (Tizen, 2016 and later) over its remote control WebSocket.
///
/// The first connect makes the TV show "Allow this device?"; once allowed it hands back a token,
/// which later connects send so the prompt doesn't appear again. Recent sets only accept the
/// encrypted port 8002 (self-signed certificate, pinned like LG's); 2016–2017 sets use plain 8001.
///
/// Not yet verified against hardware.
public actor SamsungClient: TVSession {
    public nonisolated let host: String
    public nonisolated let states: AsyncStream<ConnectionState>

    /// The name the TV shows in its prompt and its list of connected devices.
    static let clientName = "Remote"

    private let trust: CertificateTrust
    /// The token from pairing or the last connect, kept so `wake()` can reconnect without a prompt.
    private var token: String?
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var connected: CheckedContinuation<String, Error>?
    private var replies: [String: [CheckedContinuation<JSONValue, Error>]] = [:]
    private var listeners: [UUID: AsyncStream<Bool>.Continuation] = [:]
    private let stateContinuation: AsyncStream<ConnectionState>.Continuation

    public init(host: String, pinnedFingerprint: String? = nil, token: String? = nil) {
        self.host = host
        self.token = token
        trust = CertificateTrust(pinnedFingerprint: pinnedFingerprint)
        let (stream, continuation) = AsyncStream<ConnectionState>.makeStream()
        states = stream
        stateContinuation = continuation
    }

    public var certificateFingerprint: String? { trust.fingerprint }

    /// Connects, waiting while the TV shows its prompt the first time. Returns the token to keep
    /// (empty on older sets, which don't use one).
    public func connect(clientKey token: String?) async throws -> String {
        var lastError: Error = TVError.notConnected
        for url in Self.urls(host: host, token: token) {
            do {
                let issued = try await open(url, waitingForPrompt: token == nil)
                if !issued.isEmpty { self.token = issued } else if let token, !token.isEmpty { self.token = token }
                return issued
            } catch TVError.pairingRejected {
                throw TVError.pairingRejected
            } catch {
                lastError = error
            }
        }
        stateContinuation.yield(.disconnected)
        throw lastError
    }

    /// With a token, only the encrypted port: newer sets ignore tokens on 8001 and would ask again.
    /// Without one (first pairing, or a 2016–2017 set that never issues tokens), try both.
    static func urls(host: String, token: String?) -> [URL] {
        let name = Data(clientName.utf8).base64EncodedString()
        var query = "name=\(name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? name)"
        let hasToken = !(token ?? "").isEmpty
        if hasToken, let token { query += "&token=\(token)" }
        let path = "/api/v2/channels/samsung.remote.control?\(query)"
        let secure = URL(string: "wss://\(host):8002\(path)")
        let plain = URL(string: "ws://\(host):8001\(path)")
        return (hasToken ? [secure] : [secure, plain]).compactMap { $0 }
    }

    private func open(_ url: URL, waitingForPrompt: Bool) async throws -> String {
        disconnect()
        stateContinuation.yield(.connecting)
        let session = URLSession(configuration: .ephemeral, delegate: trust, delegateQueue: nil)
        let task = session.webSocketTask(with: url)
        self.session = session
        self.task = task
        task.resume()
        Task { await self.receiveLoop(task) }

        // The TV says nothing while its prompt is up, so assume it's showing after a moment.
        let prompt = Task {
            try await Task.sleep(for: .seconds(1.5))
            await self.promptShowing(task)
        }
        defer { prompt.cancel() }
        let timeout = Task {
            try await Task.sleep(for: waitingForPrompt ? .seconds(40) : .seconds(8))
            await self.giveUp(task)
        }
        defer { timeout.cancel() }

        let token: String = try await withCheckedThrowingContinuation { connected = $0 }
        stateContinuation.yield(.connected)
        broadcast(true)
        return token
    }

    public func disconnect() {
        guard task != nil else { return }
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
        closeAll(TVError.notConnected)
    }

    /// True while connected; false once the connection drops. Each call gets its own stream.
    public func connectionChanges() -> AsyncStream<Bool> {
        let (stream, continuation) = AsyncStream<Bool>.makeStream()
        let id = UUID()
        listeners[id] = continuation
        continuation.onTermination = { [weak self] _ in Task { await self?.removeListener(id) } }
        return stream
    }

    // MARK: - Commands

    /// Turns on a TV in network standby by pressing its power key. The connection dropped when
    /// the TV went off, so this reconnects first, with the saved token so the TV doesn't ask again.
    public func wake() async throws {
        if task == nil {
            _ = try await connect(clientKey: token)
        }
        try await key("KEY_POWER")
    }

    /// Presses a remote key, such as `KEY_VOLUP` or `KEY_HOME`.
    public func key(_ code: String) async throws {
        try await send(.object([
            "method": "ms.remote.control",
            "params": .object([
                "Cmd": "Click",
                "DataOfCmd": .string(code),
                "Option": "false",
                "TypeOfRemote": "SendRemoteKey",
            ]),
        ]))
    }

    /// The installed apps, as `(appId, name, type)`. Type 2 apps launch with a deep link, 4 natively.
    public func installedApps() async throws -> [(id: String, name: String, type: Int)] {
        let reply = try await emit("ed.installedApp.get", data: "", awaiting: "ed.installedApp.get")
        return (reply["data"]?.arrayValue ?? []).compactMap { app in
            guard let id = app["appId"]?.stringValue else { return nil }
            return (id, app["name"]?.stringValue ?? id, app["app_type"]?.intValue ?? 2)
        }
    }

    public func launch(appID: String, type: Int) async throws {
        try await send(.object([
            "method": "ms.channel.emit",
            "params": .object([
                "event": "ed.apps.launch",
                "to": "host",
                "data": .object([
                    "appId": .string(appID),
                    "action_type": .string(type == 4 ? "NATIVE_LAUNCH" : "DEEP_LINK"),
                ]),
            ]),
        ]))
    }

    // MARK: - Internals

    private func emit(_ event: String, data: JSONValue, awaiting reply: String) async throws -> JSONValue {
        guard task != nil else { throw TVError.notConnected }
        let message: JSONValue = .object([
            "method": "ms.channel.emit",
            "params": .object(["event": .string(event), "to": "host", "data": data]),
        ])
        return try await withCheckedThrowingContinuation { continuation in
            replies[reply, default: []].append(continuation)
            Task {
                do { try await self.send(message) } catch { await self.fail(reply, error) }
            }
            Task {
                try? await Task.sleep(for: .seconds(6))
                await self.fail(reply, TVError.timeout)
            }
        }
    }

    private func fail(_ reply: String, _ error: Error) {
        guard var waiting = replies[reply], !waiting.isEmpty else { return }
        waiting.removeFirst().resume(throwing: error)
        replies[reply] = waiting.isEmpty ? nil : waiting
    }

    private func send(_ message: JSONValue) async throws {
        guard let task else { throw TVError.notConnected }
        let data = try JSONEncoder().encode(message)
        try await task.send(.string(String(decoding: data, as: UTF8.self)))
    }

    private func promptShowing(_ task: URLSessionWebSocketTask) {
        guard task === self.task, connected != nil else { return }
        stateContinuation.yield(.awaitingPairing)
    }

    private func giveUp(_ task: URLSessionWebSocketTask) {
        guard task === self.task, let connected else { return }
        self.connected = nil
        connected.resume(throwing: TVError.timeout)
        disconnect()
    }

    private func receiveLoop(_ task: URLSessionWebSocketTask) async {
        while true {
            do {
                let message = try await task.receive()
                let data: Data
                switch message {
                case .string(let text): data = Data(text.utf8)
                case .data(let bytes): data = bytes
                @unknown default: continue
                }
                guard let json = try? JSONDecoder().decode(JSONValue.self, from: data) else { continue }
                handle(json)
            } catch {
                if task === self.task {
                    self.task = nil
                    closeAll(error)
                }
                return
            }
        }
    }

    private func handle(_ message: JSONValue) {
        guard let event = message["event"]?.stringValue else { return }
        switch event {
        case "ms.channel.connect":
            connected?.resume(returning: message["data"]?["token"]?.stringValue ?? "")
            connected = nil
        case "ms.channel.unauthorized", "ms.channel.timeOut":
            connected?.resume(throwing: TVError.pairingRejected)
            connected = nil
        default:
            guard var waiting = replies[event], !waiting.isEmpty else { return }
            waiting.removeFirst().resume(returning: message["data"] ?? .null)
            replies[event] = waiting.isEmpty ? nil : waiting
        }
    }

    private func closeAll(_ error: Error) {
        connected?.resume(throwing: error)
        connected = nil
        replies.values.flatMap { $0 }.forEach { $0.resume(throwing: error) }
        replies.removeAll()
        stateContinuation.yield(.disconnected)
        broadcast(false)
    }

    private func broadcast(_ isConnected: Bool) {
        listeners.values.forEach { $0.yield(isConnected) }
    }

    private func removeListener(_ id: UUID) {
        listeners[id] = nil
    }
}

/// What a Samsung TV says about itself at `http://<host>:8001/api/v2/`, without pairing.
public struct SamsungDeviceInfo: Sendable, Equatable {
    public var name: String?
    public var model: String?
    public var wifiMAC: String?
    /// "on" or "standby". Only newer sets report it.
    public var powerState: String?

    /// Nil if nothing at `host` answers like a Samsung TV.
    public static func fetch(host: String, timeout: TimeInterval = 2) async -> SamsungDeviceInfo? {
        guard let url = URL(string: "http://\(host):8001/api/v2/") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        guard let (data, _) = try? await URLSession(configuration: configuration).data(for: request),
              let json = try? JSONDecoder().decode(JSONValue.self, from: data)
        else { return nil }
        return parse(json)
    }

    static func parse(_ json: JSONValue) -> SamsungDeviceInfo? {
        guard let device = json["device"] else { return nil }
        let mac = device["wifiMac"]?.stringValue.flatMap { (try? WakeOnLAN.magicPacket(macAddress: $0)) != nil ? $0 : nil }
        return SamsungDeviceInfo(
            name: (device["name"]?.stringValue ?? json["name"]?.stringValue).map(SSDP.cleanName),
            model: device["modelName"]?.stringValue,
            wifiMAC: mac,
            powerState: device["PowerState"]?.stringValue
        )
    }
}
