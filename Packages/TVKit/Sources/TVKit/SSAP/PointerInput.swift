import Foundation

/// A button the TV understands on the pointer socket.
public enum RemoteButton: String, Sendable, CaseIterable {
    case up = "UP", down = "DOWN", left = "LEFT", right = "RIGHT"
    case enter = "ENTER", back = "BACK", home = "HOME"
}

/// The TV's pointer socket, which also takes remote button presses (arrows, OK, Back, Home).
///
/// Opened on first use from the address `getPointerInputSocket` returns, and reopened after it drops
/// (the TV closes it when the main connection goes). Messages are plain text, `key:value` lines
/// ending with a blank line, for example `type:button\nname:UP\n\n`.
public actor PointerInput {
    private let client: SSAPClient
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var opening: Task<URLSessionWebSocketTask, Error>?

    init(client: SSAPClient) {
        self.client = client
    }

    public func press(_ button: RemoteButton) async throws {
        try await send(Self.button(button))
    }

    static func button(_ button: RemoteButton) -> String {
        "type:button\nname:\(button.rawValue)\n\n"
    }

    // MARK: - Socket

    private func send(_ text: String) async throws {
        let socket = try await openIfNeeded()
        do {
            try await socket.send(.string(text))
        } catch {
            // Dropped: forget it so the next message reopens.
            if socket === task { close() }
            throw error
        }
    }

    private func openIfNeeded() async throws -> URLSessionWebSocketTask {
        if let task, task.state == .running { return task }
        if let opening { return try await opening.value }
        let client = client
        let opening = Task { () throws -> URLSessionWebSocketTask in
            let response = try await client.request(SSAPURI.pointerInputSocket)
            guard let path = response["socketPath"]?.stringValue, let url = URL(string: path) else {
                throw TVError.invalidResponse
            }
            let (session, task) = client.openSocket(url)
            self.adopt(session, task)
            return task
        }
        self.opening = opening
        defer { self.opening = nil }
        return try await opening.value
    }

    private func adopt(_ session: URLSession, _ task: URLSessionWebSocketTask) {
        close()
        self.session = session
        self.task = task
    }

    private func close() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
    }
}
