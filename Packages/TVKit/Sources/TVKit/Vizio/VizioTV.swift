import Foundation

/// A real Vizio SmartCast TV. Everything goes through `VizioClient` over HTTPS.
///
/// What Vizio's local API can't do: list installed apps (the app offers the well-known ones below,
/// plus the TV's inputs) or choose the sound output. Turning it on works while the TV's
/// power mode is Quick Start; in Eco mode it drops off the network when off.
///
/// Not yet verified against hardware.
public final class VizioTV: TVControlling {
    public let client: VizioClient
    private let memory = Memory()

    public init(client: VizioClient) {
        self.client = client
    }

    public var supportsSoundOutput: Bool { false }

    // MARK: - Volume

    public func volume() async throws -> VolumeStatus {
        let level = try await client.setting("audio/volume").value.intValue ?? 0
        let muted = (try? await client.setting("audio/mute").value.stringValue?.lowercased() == "on") ?? false
        await memory.set(level: level, muted: muted)
        return VolumeStatus(level: level, muted: muted)
    }

    public func setVolume(_ level: Int) async throws {
        let level = min(100, max(0, level))
        if let current = try? await client.setting("audio/volume"),
           (try? await client.changeSetting("audio/volume", to: .number(Double(level)), hash: current.hash)) != nil {
            await memory.set(level: level, muted: false)
            return
        }
        // Couldn't set it directly: step there with the volume keys.
        let from = await memory.level ?? level
        await memory.set(level: level, muted: false)
        for _ in 0..<min(abs(level - from), 25) {
            try await client.key(level > from ? .volumeUp : .volumeDown)
            try? await Task.sleep(for: .milliseconds(60))
        }
    }

    public func setMute(_ muted: Bool) async throws {
        try await client.key(muted ? .muteOn : .muteOff)
        await memory.set(muted: muted)
    }

    // MARK: - Power

    /// Vizio has no Wake-on-LAN: the TV hears the power key only while it stays on the network,
    /// which it does in Quick Start power mode. In Eco mode it can't be reached once off.
    public func powerOn() async throws { try await client.key(.powerOn) }

    public func powerOff() async throws { try await client.key(.powerOff) }

    // MARK: - Apps and inputs

    /// The TV's inputs, then the well-known apps (Vizio can't say which are installed).
    public func launchPoints() async throws -> [LaunchPoint] {
        let inputs = (try? await client.inputs()) ?? []
        return inputs.map { LaunchPoint(id: Self.inputPrefix + $0.name, title: $0.label, iconURL: nil) }
            + Self.apps.map { LaunchPoint(id: $0.id, title: $0.name, iconURL: nil) }
    }

    public func launch(appID: String) async throws {
        if appID.hasPrefix(Self.inputPrefix) {
            try await client.setInput(String(appID.dropFirst(Self.inputPrefix.count)))
        } else if let app = Self.apps.first(where: { $0.id == appID }) {
            try await client.launch(namespace: app.namespace, appID: app.appID, message: app.message)
        } else {
            throw TVError.unsupported("app \(appID)")
        }
    }

    public func foregroundAppID() async throws -> String? {
        if let current = try? await client.currentApp(),
           let app = Self.apps.first(where: { Self.sameNamespace($0.namespace, current.namespace) && $0.appID == current.appID }) {
            return app.id
        }
        guard let input = try await client.currentInput() else { return nil }
        // "CAST" or "SMARTCAST" means an app we don't know is on screen.
        return ["cast", "smartcast"].contains(input.lowercased()) ? nil : Self.inputPrefix + input
    }

    public func soundOutput() async throws -> SoundOutput { throw TVError.unsupported("sound output") }

    public func setSoundOutput(_ output: SoundOutput) async throws { throw TVError.unsupported("sound output") }

    // MARK: - Buttons

    public func press(_ button: RemoteButton) async throws {
        try await client.key(Self.key(for: button))
    }

    static func key(for button: RemoteButton) -> VizioKey {
        switch button {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .enter: return .ok
        case .back: return .back
        case .home: return .home
        }
    }

    // MARK: - Changes

    /// Vizio pushes nothing, so this checks every few seconds: the TV going off (or out of reach),
    /// the volume, and what's on screen.
    public func events() async -> AsyncStream<TVEvent> {
        AsyncStream { continuation in
            let poll = Task { [weak self] in
                var lastApp: String??
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(4))
                    guard let self, !Task.isCancelled else { return }
                    guard (try? await client.isOn()) == true else {
                        continuation.yield(.disconnected)
                        return
                    }
                    let known = await (memory.level, memory.muted)
                    if let status = try? await volume(), status.level != known.0 || status.muted != known.1 {
                        continuation.yield(.volume(status))
                    }
                    if let app = try? await foregroundAppID(), lastApp != .some(app) {
                        lastApp = .some(app)
                        continuation.yield(.foregroundApp(app))
                    }
                }
            }
            continuation.onTermination = { _ in poll.cancel() }
        }
    }

    // MARK: - Known apps

    static let inputPrefix = "vizio.input."

    struct App: Sendable {
        let name: String
        let namespace: Int
        let appID: String
        /// Some apps need a start message, such as a page address or a cast command.
        var message: String? = nil
        var id: String { "vizio.app.\(namespace).\(appID)" }
    }

    /// From pyvizio's app list (pyvizio/data/apps.json). Vizio treats namespaces 2 and 4 as the same.
    static let apps: [App] = [
        App(name: "Netflix", namespace: 3, appID: "1"),
        App(name: "YouTube", namespace: 5, appID: "1"),
        App(name: "Prime Video", namespace: 2, appID: "4"),
        App(name: "Disney+", namespace: 2, appID: "75"),
        App(name: "Hulu", namespace: 2, appID: "3"),
        App(name: "HBO Max", namespace: 2, appID: "128"),
        App(name: "Apple TV", namespace: 3, appID: "4"),
        App(name: "Peacock", namespace: 2, appID: "88"),
        App(name: "Paramount+", namespace: 2, appID: "37"),
        App(name: "Tubi", namespace: 2, appID: "61"),
        App(name: "Plex", namespace: 2, appID: "9"),
        App(name: "Pluto TV", namespace: 0, appID: "E6F74C01",
            message: #"{"CAST_NAMESPACE":"urn:x-cast:tv.pluto","CAST_MESSAGE":{"command":"initializePlayback","channel":"","episode":"","time":0}}"#),
        App(name: "WatchFree+", namespace: 2, appID: "3014",
            message: "http://127.0.0.1:12345/scfs/sctv/main.html#/watchfreeplus"),
    ]

    static func sameNamespace(_ a: Int, _ b: Int) -> Bool {
        a == b || (Set([a, b]) == [2, 4])
    }

    private actor Memory {
        var level: Int?
        var muted = false

        func set(level: Int? = nil, muted: Bool? = nil) {
            if let level { self.level = level }
            if let muted { self.muted = muted }
        }
    }
}
