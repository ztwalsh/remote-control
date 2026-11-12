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

    /// A set in network standby still answers on the network and wakes on its power key; it often
    /// ignores Wake-on-LAN. One in deep standby only hears Wake-on-LAN. Both need "Power On with Mobile".
    ///
    /// The two aren't sent together: if the packet woke the set first, the power key would turn it off again.
    public func powerOn() async throws {
        let info = await SamsungDeviceInfo.fetch(host: client.host, timeout: 2)
        if info?.powerState == "on" { return }
        if info?.powerState == "standby" {
            do {
                try await client.wake()
                return
            } catch {
                // Couldn't reconnect to press the key; fall back to Wake-on-LAN.
            }
        }
        guard !macAddresses.isEmpty else { throw TVError.missingMACAddress }
        try await WakeOnLAN.send(macAddresses: macAddresses)
    }

    public func powerOff() async throws {
        try await client.key("KEY_POWER")
    }

    // MARK: - Apps

    /// The TV's own list when it gives one. 2020 and later sets often never answer that request,
    /// so after the first timeout this checks the well-known apps instead (see `SamsungApp.catalog`).
    public func launchPoints() async throws -> [LaunchPoint] {
        if await memory.listAnswers {
            do {
                let apps = try await client.installedApps()
                if !apps.isEmpty {
                    await memory.set(appTypes: Dictionary(apps.map { ($0.id, $0.type) }, uniquingKeysWith: { first, _ in first }))
                    return apps.map { LaunchPoint(id: $0.id, title: $0.name, iconURL: nil) }
                }
            } catch TVError.timeout {
                await memory.setListAnswers(false)
            }
        }
        return await catalogApps()
    }

    /// Asks the TV about each well-known app, newest Samsung ID first, all at once.
    /// If the TV won't say for any of them, offers the whole catalog rather than nothing.
    private func catalogApps() async -> [LaunchPoint] {
        let host = client.host
        let probes = await withTaskGroup(of: Probe.self) { group -> [Probe] in
            for (index, app) in SamsungApp.catalog.enumerated() {
                group.addTask {
                    var answered = false
                    for id in app.ids {
                        switch await SamsungREST.status(host: host, appID: id) {
                        case .installed: return Probe(index: index, id: id, answered: true)
                        case .notInstalled: answered = true
                        case .unknown: break
                        }
                    }
                    return Probe(index: index, id: nil, answered: answered)
                }
            }
            var all: [Probe] = []
            for await probe in group { all.append(probe) }
            return all.sorted { $0.index < $1.index }
        }
        let found = probes.compactMap { probe in
            probe.id.map { LaunchPoint(id: $0, title: SamsungApp.catalog[probe.index].name, iconURL: nil) }
        }
        if !found.isEmpty || probes.contains(where: \.answered) { return found }
        return SamsungApp.catalog.map { LaunchPoint(id: $0.ids[0], title: $0.name, iconURL: nil) }
    }

    private struct Probe: Sendable {
        let index: Int
        let id: String?
        let answered: Bool
    }

    /// Opens an app and checks it came up, since the TV accepts launches it then ignores.
    /// For each known ID of the app: the launch style Samsung expects for it, then the other style,
    /// then Samsung's HTTP API. IDs the TV says aren't installed are skipped.
    public func launch(appID: String) async throws {
        let host = client.host
        let knownType = await memory.appTypes[appID]
        for id in SamsungApp.candidates(for: appID) {
            let status = await SamsungREST.status(host: host, appID: id)
            if status == .notInstalled { continue }
            let first = knownType ?? 2
            for type in [first, first == 4 ? 2 : 4] {
                try? await client.launch(appID: id, type: type)
                // The TV won't say whether apps are running, so trust the first try.
                if status == .unknown { return }
                if await opened(id) { return }
            }
            await SamsungREST.launch(host: host, appID: id)
            if await opened(id) { return }
        }
        throw TVError.server("The TV didn't open the app")
    }

    /// Watches the app's status for about two seconds.
    private func opened(_ id: String) async -> Bool {
        for _ in 0..<4 {
            try? await Task.sleep(for: .milliseconds(500))
            if case .installed(running: true) = await SamsungREST.status(host: client.host, appID: id) { return true }
        }
        return false
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
        case .play: return "KEY_PLAY"
        case .pause: return "KEY_PAUSE"
        case .rewind: return "KEY_REWIND"
        case .fastForward: return "KEY_FF"
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
        /// False once the TV has ignored a request for its app list.
        var listAnswers = true

        func set(level: Int? = nil, muted: Bool? = nil) {
            if let level { self.level = level }
            if let muted { self.muted = muted }
        }

        func set(appTypes: [String: Int]) { self.appTypes = appTypes }

        func setListAnswers(_ value: Bool) { listAnswers = value }
    }
}
