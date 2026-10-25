import Foundation
import Observation
import SwiftUI
import TVKit

/// One TV as the remote shows it.
struct TVState: Identifiable, Equatable {
    let id: String
    var name: String
    var isOn: Bool
    var volume: Int
    var isMuted: Bool
    var soundOutput: SoundOutput
    var foregroundAppID: String?
    var sleepEndsAt: Date?
}

/// The app's state and actions. Views read from it; every change goes through a method here,
/// which updates the screen right away and then tells the TV.
@MainActor
@Observable
final class RemoteStore {
    var tvs: [TVState]
    var selectedID: String
    let favorites: [FavoriteApp] = FavoriteApp.defaults
    /// The TV that was just turned off from the main screen, while Undo is offered.
    private(set) var undoPowerOffID: String?
    /// A sleep timer that was just cancelled, while Undo is offered.
    private(set) var undoSleep: (id: String, endsAt: Date)?

    /// True while the app shows the example TVs. Pairing the first real TV replaces them.
    private(set) var isDemo: Bool
    /// Paired TVs that are connecting right now.
    private(set) var connecting: Set<String> = []

    private var controllers: [String: any TVControlling]
    /// The connection to each paired TV. Example TVs have none.
    private var clients: [String: SSAPClient]
    private let pairings = PairingStore()
    /// The connection being paired in the Add a TV sheet, so it can be cancelled.
    private var pairingClient: SSAPClient?
    private var pendingVolume: [String: Int] = [:]
    private var sendingVolume: Set<String> = []
    private var lastLocalVolumeChange: [String: Date] = [:]
    private var undoTasks: [String: Task<Void, Never>] = [:]
    private var sleepTasks: [String: Task<Void, Never>] = [:]
    private var listeners: [String: Task<Void, Never>] = [:]
    private var started = false

    init(tvs: [TVState], controllers: [String: any TVControlling], clients: [String: SSAPClient] = [:], isDemo: Bool = false) {
        self.tvs = tvs
        selectedID = tvs.first?.id ?? ""
        self.controllers = controllers
        self.clients = clients
        self.isDemo = isDemo
    }

    var selected: TVState {
        tvs.first { $0.id == selectedID } ?? tvs[0]
    }

    // MARK: - TVs

    func select(_ id: String) {
        guard tvs.contains(where: { $0.id == id }) else { return }
        selectedID = id
        undoPowerOffID = nil
        undoSleep = nil
    }

    func setPower(_ isOn: Bool, for id: String, offerUndo: Bool = false) {
        update(id) { tv in
            tv.isOn = isOn
            if !isOn {
                tv.foregroundAppID = nil
                tv.sleepEndsAt = nil
            }
        }
        if !isOn { sleepTasks[id]?.cancel() }

        undoTasks["power"]?.cancel()
        if !isOn && offerUndo {
            undoPowerOffID = id
            undoTasks["power"] = Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                self?.undoPowerOffID = nil
            }
        } else {
            undoPowerOffID = nil
        }

        guard let controller = controllers[id] else { return }
        Task {
            if isOn {
                try? await controller.powerOn()
                // A real TV drops its connection while off; reconnect once it has woken.
                if clients[id] != nil { await reconnectAfterWake(id) }
            } else {
                try? await controller.powerOff()
            }
        }
    }

    func undoPowerOff() {
        guard let id = undoPowerOffID else { return }
        setPower(true, for: id)
    }

    // MARK: - Volume

    /// Updates the screen immediately; sends to the TV at most every 50 ms, always with the latest value.
    func setVolume(_ level: Int) {
        let id = selectedID
        let level = min(100, max(0, level))
        update(id) { tv in
            tv.volume = level
            tv.isMuted = false
        }
        lastLocalVolumeChange[id] = .now
        pendingVolume[id] = level
        guard !sendingVolume.contains(id) else { return }
        sendingVolume.insert(id)
        Task { await flushVolume(for: id) }
    }

    func stepVolume(by delta: Int) {
        setVolume(selected.volume + delta)
    }

    func toggleMute() {
        let id = selectedID
        let muted = !selected.isMuted
        update(id) { $0.isMuted = muted }
        let controller = controllers[id]
        Task { try? await controller?.setMute(muted) }
    }

    private func flushVolume(for id: String) async {
        while let level = pendingVolume.removeValue(forKey: id) {
            try? await controllers[id]?.setVolume(level)
            try? await Task.sleep(for: .milliseconds(50))
        }
        sendingVolume.remove(id)
    }

    // MARK: - Sound out

    func setSoundOutput(_ output: SoundOutput) {
        let id = selectedID
        update(id) { $0.soundOutput = output }
        let controller = controllers[id]
        Task { try? await controller?.setSoundOutput(output) }
    }

    // MARK: - Apps

    func launch(_ app: FavoriteApp) {
        let id = selectedID
        update(id) { $0.foregroundAppID = app.id }
        let controller = controllers[id]
        Task { try? await controller?.launch(appID: app.id) }
    }

    func appName(for appID: String?) -> String? {
        guard let appID else { return nil }
        return favorites.first { $0.id == appID }?.name
    }

    // MARK: - Sleep timer

    /// Sets the timer for the selected TV. Zero cancels it, with Undo.
    ///
    /// For now the app turns the TV off itself, which only works while the app is open.
    /// Phase 0 decides between the TV's own timer and a HomeKit automation (docs/PLAN.md, section 4).
    func setSleepTimer(minutes: Int) {
        let id = selectedID
        if minutes <= 0 {
            if let endsAt = selected.sleepEndsAt {
                undoSleep = (id, endsAt)
                undoTasks["sleep"]?.cancel()
                undoTasks["sleep"] = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled else { return }
                    self?.undoSleep = nil
                }
            }
            update(id) { $0.sleepEndsAt = nil }
            sleepTasks[id]?.cancel()
            return
        }
        undoSleep = nil
        schedule(endsAt: .now.addingTimeInterval(TimeInterval(minutes * 60)), for: id)
    }

    func undoSleepCancel() {
        guard let undo = undoSleep, undo.endsAt > .now else { return }
        undoSleep = nil
        schedule(endsAt: undo.endsAt, for: undo.id)
    }

    private func schedule(endsAt: Date, for id: String) {
        update(id) { $0.sleepEndsAt = endsAt }
        sleepTasks[id]?.cancel()
        sleepTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, endsAt.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.setPower(false, for: id)
        }
    }

    // MARK: - Status

    func status(for tv: TVState) -> String {
        if connecting.contains(tv.id) && !tv.isOn { return "Connecting…" }
        if !tv.isOn { return "Off" }
        if let endsAt = tv.sleepEndsAt {
            let minutes = max(1, Int((endsAt.timeIntervalSinceNow / 60).rounded(.up)))
            return "Sleeping in \(Self.duration(minutes: minutes))"
        }
        if let app = appName(for: tv.foregroundAppID) { return "Watching \(app)" }
        return "On"
    }

    nonisolated static func duration(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "\(hours) hr" : "\(hours) hr \(rest) min"
    }

    // MARK: - Paired TVs

    /// Pairs with the TV at `host` and selects it. The first time, the TV asks "Allow this device?";
    /// `onPrompt` runs when it does. Throws if the TV can't be reached or the prompt is declined.
    func addTV(name: String, host: String, onPrompt: @escaping @MainActor () -> Void) async throws {
        let client = SSAPClient(host: host)
        pairingClient = client
        defer { pairingClient = nil }
        let prompts = Task { @MainActor in
            for await state in client.states where state == .awaitingPairing { onPrompt() }
        }
        defer { prompts.cancel() }

        let clientKey = try await client.connect(clientKey: nil)
        let fingerprint = await client.certificateFingerprint
        let macAddress = try? await WebOSTV(client: client, macAddress: nil).fetchMACAddress()
        let id = UUID().uuidString
        try pairings.save(Pairing(clientKey: clientKey, certificateFingerprint: fingerprint, macAddress: macAddress), for: id)
        SavedTVs.save(SavedTVs.load() + [SavedTV(id: id, name: name, host: host)])

        if isDemo {
            listeners.values.forEach { $0.cancel() }
            listeners = [:]
            controllers = [:]
            tvs = []
            isDemo = false
        }
        let controller = WebOSTV(client: client, macAddress: macAddress)
        clients[id] = client
        controllers[id] = controller
        tvs.append(TVState(id: id, name: name, isOn: true, volume: 0, isMuted: false, soundOutput: .tvSpeaker))
        select(id)
        await refresh(id, from: controller)
        listen(to: id, controller)
    }

    /// Stops a pairing in progress, for example when the Add a TV sheet is closed.
    func cancelPairing() {
        guard let client = pairingClient else { return }
        Task { await client.disconnect() }
    }

    /// Forgets a paired TV. Removing the last one brings back the example TVs.
    func removeTV(_ id: String) {
        guard let client = clients.removeValue(forKey: id) else { return }
        Task { await client.disconnect() }
        listeners.removeValue(forKey: id)?.cancel()
        controllers[id] = nil
        pairings.remove(for: id)
        SavedTVs.save(SavedTVs.load().filter { $0.id != id })
        tvs.removeAll { $0.id == id }

        if tvs.isEmpty {
            let demo = RemoteStore.demo()
            tvs = demo.tvs
            controllers = demo.controllers
            isDemo = true
            for (id, controller) in controllers { listen(to: id, controller) }
        }
        if !tvs.contains(where: { $0.id == selectedID }) { select(tvs[0].id) }
    }

    /// Reconnects every paired TV. iOS drops connections while the app is in the background.
    func reconnect() {
        for id in clients.keys {
            Task { await connect(id) }
        }
    }

    /// Connects with the stored client key, then reads the TV's current state.
    /// A TV that can't be reached is shown as off, unless it's still waking up.
    @discardableResult
    private func connect(_ id: String, markOffOnFailure: Bool = true) async -> Bool {
        guard let client = clients[id], let controller = controllers[id], !connecting.contains(id) else { return false }
        connecting.insert(id)
        defer { connecting.remove(id) }
        // Stop listening first: reconnecting closes the old socket, which reports a disconnect.
        listeners.removeValue(forKey: id)?.cancel()
        do {
            _ = try await client.connect(clientKey: pairings.load(for: id)?.clientKey)
        } catch {
            if markOffOnFailure { update(id) { $0.isOn = false } }
            return false
        }
        update(id) { $0.isOn = true }
        await refresh(id, from: controller)
        listen(to: id, controller)
        return true
    }

    /// webOS takes several seconds to boot after Wake-on-LAN. Keeps trying for about 20 seconds.
    private func reconnectAfterWake(_ id: String) async {
        for _ in 0..<10 {
            try? await Task.sleep(for: .seconds(2))
            guard tvs.contains(where: { $0.id == id && $0.isOn }) else { return }
            if await connect(id, markOffOnFailure: false) { return }
        }
        update(id) { $0.isOn = false }
    }

    private func refresh(_ id: String, from controller: any TVControlling) async {
        if let status = try? await controller.volume() {
            update(id) { tv in
                tv.volume = status.level
                tv.isMuted = status.muted
                if let output = status.soundOutput { tv.soundOutput = output }
            }
        }
        if let output = try? await controller.soundOutput() {
            update(id) { $0.soundOutput = output }
        }
        if let appID = try? await controller.foregroundAppID() {
            update(id) { $0.foregroundAppID = appID }
        }
    }

    // MARK: - Listening to the TVs

    /// Connects to the paired TVs and starts following changes pushed by each TV,
    /// such as someone using the physical remote.
    func start() {
        guard !started else { return }
        started = true
        for (id, controller) in controllers where clients[id] == nil {
            listen(to: id, controller)
        }
        reconnect()
    }

    private func listen(to id: String, _ controller: any TVControlling) {
        listeners[id]?.cancel()
        listeners[id] = Task { [weak self] in
            for await event in await controller.events() {
                guard !Task.isCancelled else { return }
                self?.apply(event, to: id)
            }
        }
    }

    private func apply(_ event: TVEvent, to id: String) {
        switch event {
        case .volume(let status):
            // Ignore echoes of our own recent changes so the bar doesn't jump while dragging.
            if let last = lastLocalVolumeChange[id], Date.now.timeIntervalSince(last) < 0.6 { return }
            update(id) { tv in
                tv.volume = status.level
                tv.isMuted = status.muted
                if let output = status.soundOutput { tv.soundOutput = output }
            }
        case .soundOutput(let output):
            update(id) { $0.soundOutput = output }
        case .foregroundApp(let appID):
            update(id) { $0.foregroundAppID = appID }
        case .disconnected:
            // A real TV closes the connection when it turns off. iOS also drops it while the app
            // is in the background; returning to the app reconnects.
            update(id) { $0.isOn = false }
        }
    }

    private func update(_ id: String, _ change: (inout TVState) -> Void) {
        guard let index = tvs.firstIndex(where: { $0.id == id }) else { return }
        change(&tvs[index])
    }
}

extension RemoteStore {
    /// The paired TVs, or the example TVs until one is paired.
    static func load() -> RemoteStore {
        let saved = SavedTVs.load()
        guard !saved.isEmpty else { return demo() }
        let pairings = PairingStore()
        var clients: [String: SSAPClient] = [:]
        var controllers: [String: any TVControlling] = [:]
        for tv in saved {
            let pairing = pairings.load(for: tv.id)
            let client = SSAPClient(host: tv.host, pinnedFingerprint: pairing?.certificateFingerprint)
            clients[tv.id] = client
            controllers[tv.id] = WebOSTV(client: client, macAddress: pairing?.macAddress)
        }
        let tvs = saved.map {
            TVState(id: $0.id, name: $0.name, isOn: false, volume: 0, isMuted: false, soundOutput: .tvSpeaker)
        }
        return RemoteStore(tvs: tvs, controllers: controllers, clients: clients)
    }

    /// Three example TVs backed by `MockTV`, so the app runs in the simulator before pairing exists.
    static func demo() -> RemoteStore {
        let tvs = [
            TVState(id: "living", name: "Living room", isOn: true, volume: 18, isMuted: false,
                    soundOutput: .hdmiARC, foregroundAppID: "netflix"),
            TVState(id: "bedroom", name: "Bedroom", isOn: false, volume: 12, isMuted: false,
                    soundOutput: .tvSpeaker),
            TVState(id: "basement", name: "Basement", isOn: true, volume: 30, isMuted: false,
                    soundOutput: .bluetooth, foregroundAppID: "youtube.leanback.v4"),
        ]
        let controllers: [String: any TVControlling] = Dictionary(uniqueKeysWithValues: tvs.map { tv in
            (tv.id, MockTV(volume: tv.volume, soundOutput: tv.soundOutput, foregroundAppID: tv.foregroundAppID, isOn: tv.isOn) as any TVControlling)
        })
        return RemoteStore(tvs: tvs, controllers: controllers, isDemo: true)
    }
}
