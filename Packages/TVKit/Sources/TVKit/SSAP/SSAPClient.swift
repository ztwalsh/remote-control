import Foundation

public enum ConnectionState: Sendable, Equatable {
    case disconnected
    case connecting
    /// The TV is showing its "Allow this device?" prompt.
    case awaitingPairing
    case connected
}

/// One WebSocket connection to one TV: pairing, request/response matching and subscriptions.
public actor SSAPClient {
    public nonisolated let host: String
    public nonisolated let states: AsyncStream<ConnectionState>

    private let port: Int
    private let trust: CertificateTrust
    private let requestTimeout: Duration
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var nextID = 1
    private var pending: [String: CheckedContinuation<JSONValue, Error>] = [:]
    private var subscriptions: [String: AsyncThrowingStream<JSONValue, Error>.Continuation] = [:]
    private var registration: CheckedContinuation<String, Error>?
    private let stateContinuation: AsyncStream<ConnectionState>.Continuation

    /// - Parameters:
    ///   - port: 3001 is the encrypted port; recent firmware has dropped the plain 3000.
    ///   - pinnedFingerprint: the certificate fingerprint saved at pairing, if any.
    public init(host: String, port: Int = 3001, pinnedFingerprint: String? = nil, requestTimeout: Duration = .seconds(8)) {
        self.host = host
        self.port = port
        self.requestTimeout = requestTimeout
        trust = CertificateTrust(pinnedFingerprint: pinnedFingerprint)
        let (stream, continuation) = AsyncStream<ConnectionState>.makeStream()
        states = stream
        stateContinuation = continuation
    }

    /// The certificate fingerprint seen on this connection. Persist it with the client key.
    public var certificateFingerprint: String? { trust.fingerprint }

    /// Opens the socket and registers. Resolves once the TV accepts, returning the client key to keep.
    /// The first time, this waits while the TV shows its pairing prompt.
    public func connect(clientKey: String?) async throws -> String {
        disconnect()
        guard let url = URL(string: "wss://\(host):\(port)") else { throw TVError.notConnected }
        stateContinuation.yield(.connecting)

        let session = URLSession(configuration: .ephemeral, delegate: trust, delegateQueue: nil)
        let task = session.webSocketTask(with: url)
        self.session = session
        self.task = task
        task.resume()
        Task { await self.receiveLoop(task) }

        let message = SSAPOutgoing(
            type: "register",
            id: SSAPRegistration.messageID,
            payload: SSAPRegistration.payload(clientKey: clientKey)
        )
        let key: String = try await withCheckedThrowingContinuation { continuation in
            registration = continuation
            Task { await self.sendRegistration(message) }
        }
        stateContinuation.yield(.connected)
        return key
    }

    public func disconnect() {
        guard task != nil else { return }
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
        closeAll(TVError.notConnected)
    }

    /// Sends a request and waits for its response payload.
    public func request(_ uri: String, payload: JSONValue? = nil) async throws -> JSONValue {
        guard task != nil else { throw TVError.notConnected }
        let id = makeID()
        let message = SSAPOutgoing(type: "request", id: id, uri: uri, payload: payload)
        let timeout = requestTimeout
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            Task { await self.dispatch(message) }
            Task {
                try? await Task.sleep(for: timeout)
                await self.expire(id)
            }
        }
    }

    /// Subscribes to an endpoint. The TV sends the current value, then every change.
    public func subscribe(_ uri: String, payload: JSONValue? = nil) -> AsyncThrowingStream<JSONValue, Error> {
        let id = makeID()
        let (stream, continuation) = AsyncThrowingStream<JSONValue, Error>.makeStream()
        guard task != nil else {
            continuation.finish(throwing: TVError.notConnected)
            return stream
        }
        subscriptions[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.unsubscribe(id) }
        }
        Task { await self.dispatch(SSAPOutgoing(type: "subscribe", id: id, uri: uri, payload: payload)) }
        return stream
    }

    // MARK: - Internals

    private func makeID() -> String {
        defer { nextID += 1 }
        return "req_\(nextID)"
    }

    private func send(_ message: SSAPOutgoing) async throws {
        guard let task else { throw TVError.notConnected }
        let data = try JSONEncoder().encode(message)
        try await task.send(.string(String(decoding: data, as: UTF8.self)))
    }

    private func sendRegistration(_ message: SSAPOutgoing) async {
        do {
            try await send(message)
        } catch {
            registration?.resume(throwing: error)
            registration = nil
        }
    }

    private func dispatch(_ message: SSAPOutgoing) async {
        do {
            try await send(message)
        } catch {
            pending.removeValue(forKey: message.id)?.resume(throwing: error)
            subscriptions.removeValue(forKey: message.id)?.finish(throwing: error)
        }
    }

    private func expire(_ id: String) {
        pending.removeValue(forKey: id)?.resume(throwing: TVError.timeout)
    }

    private func unsubscribe(_ id: String) async {
        guard subscriptions.removeValue(forKey: id) != nil else { return }
        try? await send(SSAPOutgoing(type: "unsubscribe", id: id))
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
                guard let incoming = try? JSONDecoder().decode(SSAPIncoming.self, from: data) else { continue }
                handle(incoming)
            } catch {
                if task === self.task {
                    self.task = nil
                    closeAll(error)
                }
                return
            }
        }
    }

    private func handle(_ message: SSAPIncoming) {
        if message.id == SSAPRegistration.messageID {
            switch message.type {
            case "registered":
                registration?.resume(returning: message.payload?["client-key"]?.stringValue ?? "")
                registration = nil
            case "response" where message.payload?["pairingType"]?.stringValue == "PROMPT":
                stateContinuation.yield(.awaitingPairing)
            case "error":
                registration?.resume(throwing: TVError.pairingRejected)
                registration = nil
            default:
                break
            }
            return
        }

        guard let id = message.id else { return }
        if message.type == "error" {
            let error = TVError.server(message.error ?? "Unknown error")
            pending.removeValue(forKey: id)?.resume(throwing: error)
            subscriptions.removeValue(forKey: id)?.finish(throwing: error)
            return
        }

        let payload = message.payload ?? .null
        if let continuation = pending.removeValue(forKey: id) {
            if payload["returnValue"]?.boolValue == false {
                continuation.resume(throwing: TVError.server(payload["errorText"]?.stringValue ?? "Request failed"))
            } else {
                continuation.resume(returning: payload)
            }
        } else if let subscription = subscriptions[id] {
            subscription.yield(payload)
        }
    }

    private func closeAll(_ error: Error) {
        registration?.resume(throwing: error)
        registration = nil
        pending.values.forEach { $0.resume(throwing: error) }
        pending.removeAll()
        subscriptions.values.forEach { $0.finish(throwing: error) }
        subscriptions.removeAll()
        stateContinuation.yield(.disconnected)
    }
}
