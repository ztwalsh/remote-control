import Foundation

/// A real Samsung Smart TV (Tizen). Buttons and apps go over `SamsungClient`; exact volume and
/// mute over UPnP when the set offers it, otherwise volume keys.
///
/// What Samsung's local API can't do: choose the sound output, or say which app is on screen.
/// Turning it on needs "Power On with Mobile" (Settings › General › Network › Expert Settings).
///
/// Not yet verified against hardware.
public final class SamsungTV: TVControlling {
    public let client: SamsungClient
    public let macAddresses: [String]
    private let rendering: RenderingControl?
    private let memory = Memory()

    public init(client: SamsungClient, macAddresses: [String]) {
        self.client = client
        self.macAddresses = macAddresses
        rendering = RenderingControl(host: client.host)
    }

    public var supportsSoundOutput: Bool { false }

    // MARK: - Volume

    public func volume() async throws -> VolumeStatus {
        guard let rendering else { throw TVError.unsupported("volume") }
        let level = try await rendering.volume()
        let muted = (try? await rendering.isMuted()) ?? false
        await memory.set(level: level, muted: muted)
        return VolumeStatus(level: level, muted: muted)
    }

    public func setVolume(_ level: Int) async throws {
        let level = min(100, max(0, level))
        if let rendering, (try? await rendering.setVolume(level)) != nil {
            await memory.set(level: level, muted: false)
            return
        }
        // No exact volume on this set: step there with the volume keys from the last level seen.
        let from = await memory.level ?? level
        await memory.set(level: level, muted: false)
        let steps = min(abs(level - from), 25)
        for _ in 0..<steps {
            try await client.key(level > from ? "KEY_VOLUP" : "KEY_VOLDOWN")
            try? await Task.sleep(for: .milliseconds(60))
        }
    }

    public func setMute(_ muted: Bool) async throws {
        if let rendering, (try? await rendering.setMute(muted)) != nil {
            await memory.set(muted: muted)
            return
        }
        // The mute key toggles, so only press it when the state needs to change.
        if await memory.muted != muted { try await client.key("KEY_MUTE") }
        await memory.set(muted: muted)
    }

    // MARK: - Power

    public func powerOn() async throws {
        if !macAddresses.isEmpty { try? await WakeOnLAN.send(macAddresses: macAddresses) }
        // Newer sets keep the network up in standby and wake on the power key.
        if await SamsungDeviceInfo.fetch(host: client.host, timeout: 1)?.powerState == "standby" {
            try? await client.key("KEY_POWER")
        }
        if macAddresses.isEmpty { throw TVError.missingMACAddress }
    }

    public func powerOff() async throws {
        try await client.key("KEY_POWER")
    }

    // MARK: - Apps

    public func launchPoints() async throws -> [LaunchPoint] {
        let apps = try await client.installedApps()
        await memory.set(appTypes: Dictionary(apps.map { ($0.id, $0.type) }, uniquingKeysWith: { first, _ in first }))
        return apps.map { LaunchPoint(id: $0.id, title: $0.name, iconURL: nil) }
    }

    public func launch(appID: String) async throws {
        try await client.launch(appID: appID, type: await memory.appTypes[appID] ?? 2)
    }

    public func foregroundAppID() async throws -> String? { nil }

    public func soundOutput() async throws -> SoundOutput { throw TVError.unsupported("sound output") }

    public func setSoundOutput(_ output: SoundOutput) async throws { throw TVError.unsupported("sound output") }

    // MARK: - Buttons

    public func press(_ button: RemoteButton) async throws {
        try await client.key(Self.key(for: button))
    }

    static func key(for button: RemoteButton) -> String {
        switch button {
        case .up: return "KEY_UP"
        case .down: return "KEY_DOWN"
        case .left: return "KEY_LEFT"
        case .right: return "KEY_RIGHT"
        case .enter: return "KEY_ENTER"
        case .back: return "KEY_RETURN"
        case .home: return "KEY_HOME"
        }
    }

    // MARK: - Changes

    /// Samsung pushes nothing, so this checks the volume every few seconds (picking up the physical
    /// remote) and reports when the connection drops.
    public func events() async -> AsyncStream<TVEvent> {
        let changes = await client.connectionChanges()
        let rendering = rendering
        let memory = memory
        return AsyncStream { continuation in
            let watch = Task {
                for await isConnected in changes where !isConnected {
                    continuation.yield(.disconnected)
                }
            }
            let poll = Task {
                guard let rendering else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(4))
                    guard let level = try? await rendering.volume() else { continue }
                    let muted = (try? await rendering.isMuted()) ?? false
                    let known = await (memory.level, memory.muted)
                    if known.0 != level || known.1 != muted {
                        await memory.set(level: level, muted: muted)
                        continuation.yield(.volume(VolumeStatus(level: level, muted: muted)))
                    }
                }
            }
            continuation.onTermination = { _ in
                watch.cancel()
                poll.cancel()
            }
        }
    }

    /// What this TV last reported, since some calls only step or toggle.
    private actor Memory {
        var level: Int?
        var muted = false
        var appTypes: [String: Int] = [:]

        func set(level: Int? = nil, muted: Bool? = nil) {
            if let level { self.level = level }
            if let muted { self.muted = muted }
        }

        func set(appTypes: [String: Int]) { self.appTypes = appTypes }
    }
}
