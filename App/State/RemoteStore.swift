import Foundation
import Observation
import UIKit
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
    /// The apps installed on each TV, once fetched. Nil until then.
    private(set) var installedApps: [String: [LaunchPoint]] = [:]
    /// Each TV's pinned apps. A TV with no entry shows the default favorites.
    private var pins: [String: [PinnedApp]] = PinnedApps.load()
    /// A sleep timer that was just cancelled, while Undo is offered.
    private(set) var undoSleep: (id: String, endsAt: Date)?

    /// True while the app shows the example TVs. Pairing the first real TV replaces them.
    private(set) var isDemo: Bool
    /// Paired TVs that are connecting right now.
    private(set) var connecting: Set<String> = []

    private var controllers: [String: any TVControlling]
    /// The connection to each paired TV. Example TVs have none.
    private var clients: [String: any TVSession]
    private let pairings = PairingStore()
    /// The connection being paired in the Add a TV sheet, so it can be cancelled.
    private var pairingClient: (any TVSession)?
    private var pendingVolume: [String: Int] = [:]
    private var sendingVolume: Set<String> = []
    private var lastLocalVolumeChange: [String: Date] = [:]
    private var undoTasks: [String: Task<Void, Never>] = [:]
    private var sleepTasks: [String: Task<Void, Never>] = [:]
    private var listeners: [String: Task<Void, Never>] = [:]
    private var started = false

    init(tvs: [TVState], controllers: [String: any TVControlling], clients: [String: any TVSession] = [:], isDemo: Bool = false) {
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
        undoSleep = nil
    }

    func setPower(_ isOn: Bool, for id: String) {
        update(id) { tv in
            tv.isOn = isOn
            if !isOn {
                tv.foregroundAppID = nil
                tv.sleepEndsAt = nil
            }
        }
        if !isOn { sleepTasks[id]?.cancel() }

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

    /// What each TV's outputs are known to be. webOS has no call that lists them, so the app keeps
    /// every output a TV has reported or accepted, and every one it refused.
    private(set) var outputMemory: [String: OutputMemory] = OutputMemory.load()

    /// False for Samsung, which doesn't let other apps choose where its sound goes.
    var supportsSoundOutput: Bool {
        controllers[selectedID]?.supportsSoundOutput ?? true
    }

    /// The selected TV's outputs: TV speakers, then every output it has used. The example TVs show all.
    var availableOutputs: [SoundOutput] {
        if isDemo { return SoundOutput.choices }
        let seen = (outputMemory[selectedID]?.seen ?? []).map(SoundOutput.init(rawValue:))
        var list: [SoundOutput] = [.tvSpeaker]
        for output in seen + [selected.soundOutput] where !list.contains(output) { list.append(output) }
        return list
    }

    /// Common outputs this TV hasn't used or refused yet, offered to try.
    var untriedOutputs: [SoundOutput] {
        if isDemo { return [] }
        let refused = Set(outputMemory[selectedID]?.refused ?? [])
        return SoundOutput.choices.filter { !availableOutputs.contains($0) && !refused.contains($0.rawValue) }
    }

    /// Switches the selected TV's output. Returns false, and puts the old output back, if the TV refuses;
    /// a refused output is then hidden for that TV.
    @discardableResult
    func setSoundOutput(_ output: SoundOutput) async -> Bool {
        let id = selectedID
        let previous = selected.soundOutput
        update(id) { $0.soundOutput = output }
        guard let controller = controllers[id] else { return true }
        do {
            try await controller.setSoundOutput(output)
            rememberOutput(output, for: id)
            return true
        } catch {
            update(id) { $0.soundOutput = previous }
            if case TVError.server = error {
                var memory = outputMemory[id] ?? OutputMemory()
                if !memory.seen.contains(output.rawValue), !memory.refused.contains(output.rawValue) {
                    memory.refused.append(output.rawValue)
                }
                setOutputMemory(memory, for: id)
            }
            return false
        }
    }

    private func rememberOutput(_ output: SoundOutput, for id: String) {
        var memory = outputMemory[id] ?? OutputMemory()
        guard !memory.seen.contains(output.rawValue) else { return }
        memory.seen.append(output.rawValue)
        memory.refused.removeAll { $0 == output.rawValue }
        setOutputMemory(memory, for: id)
    }

    private func setOutputMemory(_ memory: OutputMemory, for id: String) {
        outputMemory[id] = memory
        guard !isDemo else { return }
        OutputMemory.save(outputMemory.filter { key, _ in clients[key] != nil })
    }

    // MARK: - Apps

    func launch(appID: String) {
        let id = selectedID
        update(id) { $0.foregroundAppID = appID }
        let controller = controllers[id]
        Task { try? await controller?.launch(appID: appID) }
    }

    func appName(for appID: String?) -> String? {
        guard let appID else { return nil }
        return installedApps[selectedID]?.first { $0.id == appID }?.title
            ?? pins[selectedID]?.first { $0.id == appID }?.title
            ?? FavoriteApp.defaults.first { $0.id == appID }?.name
    }

    @ObservationIgnored private var icons: [URL: UIImage] = [:]
    @ObservationIgnored private var iconLoads: [URL: Task<UIImage?, Never>] = [:]

    /// An app icon the TV serves, fetched through that TV's trusted connection and kept in memory.
    func icon(for url: URL) async -> UIImage? {
        if let cached = icons[url] { return cached }
        if let loading = iconLoads[url] { return await loading.value }
        // Only LG serves icons; Samsung apps show their bundled logo or first letter.
        let client = clients.values.lazy.compactMap { $0 as? SSAPClient }.first { $0.host == url.host }
        let load = Task<UIImage?, Never> {
            let data: Data?
            if let client {
                data = try? await client.resource(url)
            } else {
                data = try? await URLSession.shared.data(from: url).0
            }
            return data.flatMap(UIImage.init(data:))
        }
        iconLoads[url] = load
        let image = await load.value
        iconLoads[url] = nil
        if let image { icons[url] = image }
        return image
    }

    /// True when this input is what the selected TV is showing.
    func foregroundIsInput(_ appID: String) -> Bool {
        selected.foregroundAppID == appID
    }

    /// The selected TV's Favorites grid.
    var favorites: [PinnedApp] {
        pins[selectedID] ?? FavoriteApp.defaults.map(\.pinned)
    }

    func isPinned(_ appID: String) -> Bool {
        favorites.contains { $0.id == appID }
    }

    /// Adds the app to the end of the selected TV's Favorites, or removes it.
    func togglePin(_ app: LaunchPoint) {
        var list = favorites
        if let index = list.firstIndex(where: { $0.id == app.id }) {
            list.remove(at: index)
        } else {
            list.append(PinnedApp(app))
        }
        setPins(list, for: selectedID)
    }

    func unpin(_ appID: String) {
        setPins(favorites.filter { $0.id != appID }, for: selectedID)
    }

    func movePin(from source: IndexSet, to destination: Int) {
        var list = favorites
        list.move(fromOffsets: source, toOffset: destination)
        setPins(list, for: selectedID)
    }

    /// Fetches the selected TV's installed apps (or refreshes them).
    func loadApps() async {
        let id = selectedID
        if isDemo {
            installedApps[id] = FavoriteApp.defaults.map { LaunchPoint(id: $0.id, title: $0.name, iconURL: nil) }
            return
        }
        guard let controller = controllers[id], let points = try? await controller.launchPoints() else { return }
        applyInstalled(points, to: id)
    }

    private func applyInstalled(_ points: [LaunchPoint], to id: String) {
        // A TV can list one app more than once (one entry per launch point); keep the first.
        var seen = Set<String>()
        let apps = points.filter { seen.insert($0.id).inserted }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        installedApps[id] = apps
        if let current = pins[id] {
            // Keep names and icon addresses current (the icon address includes the TV's IP).
            let byID = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) })
            setPins(current.map { pin in byID[pin.id].map(PinnedApp.init) ?? pin }, for: id)
        } else {
            // First time: start from the default favorites this TV actually has, matched by ID (LG)
            // or by name (Samsung uses its own IDs).
            let seeded = FavoriteApp.defaults.compactMap { favorite in
                apps.first { $0.id == favorite.id }
                    ?? apps.first { $0.title.caseInsensitiveCompare(favorite.name) == .orderedSame }
            }
            setPins(seeded.map(PinnedApp.init), for: id)
        }
    }

    private func setPins(_ list: [PinnedApp], for id: String) {
        pins[id] = list
        guard !isDemo else { return }
        PinnedApps.save(pins.filter { key, _ in clients[key] != nil })
    }

    // MARK: - Navigate

    /// Set when the TV refuses remote navigation, which happens for TVs paired before it
    /// existed: their pairing didn't ask for that permission.
    private(set) var pointerRefused = false

    func press(_ button: RemoteButton) {
        pointer { try await $0.press(button) }
    }

    private func pointer(_ action: @escaping @Sendable (any TVControlling) async throws -> Void) {
        guard let controller = controllers[selectedID] else { return }
        Task {
            do {
                try await action(controller)
                pointerRefused = false
            } catch TVError.server(let message) where message.localizedCaseInsensitiveContains("permission") {
                pointerRefused = true
            } catch {}
        }
    }

    /// Pairs the selected TV again, so it grants permissions added since it was first paired.
    /// The TV shows its "Allow this device?" prompt. Keeps the TV's place, name and settings;
    /// if pairing fails, the old pairing stays as it was.
    func repairSelected(onPrompt: @escaping @MainActor () -> Void) async throws {
        let id = selectedID
        guard let saved = SavedTVs.load().first(where: { $0.id == id }), saved.kind == .lg else { return }
        let client = SSAPClient(host: saved.host)
        pairingClient = client
        defer { pairingClient = nil }
        let prompts = Task { @MainActor in
            for await state in client.states where state == .awaitingPairing { onPrompt() }
        }
        defer { prompts.cancel() }

        let clientKey = try await client.connect(clientKey: nil)
        let fingerprint = await client.certificateFingerprint
        let fetched = (try? await WebOSTV(client: client, macAddresses: []).fetchMACAddresses()) ?? []
        let macAddresses = fetched.isEmpty ? (pairings.load(for: id)?.wakeAddresses ?? []) : fetched
        try pairings.save(Pairing(clientKey: clientKey, certificateFingerprint: fingerprint, macAddresses: macAddresses), for: id)

        listeners.removeValue(forKey: id)?.cancel()
        if let old = clients[id] { Task { await old.disconnect() } }
        let controller = WebOSTV(client: client, macAddresses: macAddresses)
        clients[id] = client
        controllers[id] = controller
        update(id) { $0.isOn = true }
        pointerRefused = false
        await refresh(id, from: controller)
        listen(to: id, controller)
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

    // MARK: - Finding TVs

    /// LG and Samsung TVs on the Wi-Fi that aren't paired yet. Takes about three seconds.
    func discoverTVs() async -> [DiscoveredTV] {
        let paired = Set(SavedTVs.load().map(\.host))
        let found = (try? await SSDPBrowser().search()) ?? []
        return found.filter { !paired.contains($0.host) }
    }

    // MARK: - Paired TVs

    /// Pairs with the TV at `host` and selects it. The first time, the TV asks "Allow this device?";
    /// `onPrompt` runs when it does. Throws if the TV can't be reached or the prompt is declined.
    /// `brand` is nil when the address was typed; the app then asks the TV what it is.
    /// Vizio pairs with a PIN the TV shows: `onPIN` asks for it (nil cancels).
    func addTV(
        name: String, host: String, brand: TVBrand?,
        onPrompt: @escaping @MainActor () -> Void,
        onPIN: @escaping @MainActor @Sendable () async -> String?
    ) async throws {
        let kind: TVBrand
        if let brand { kind = brand } else { kind = await Self.detectBrand(host: host) }
        let client = Self.session(kind, host: host, pairing: nil)
        if let vizio = client as? VizioClient {
            await vizio.setPINProvider { await onPIN() }
        }
        pairingClient = client
        defer { pairingClient = nil }
        let prompts = Task { @MainActor in
            for await state in client.states where state == .awaitingPairing { onPrompt() }
        }
        defer { prompts.cancel() }

        let clientKey = try await client.connect(clientKey: nil)
        let fingerprint = await client.certificateFingerprint
        let fetched = await Self.fetchMACAddresses(client)
        let macAddresses = fetched.isEmpty ? nil : fetched
        let id = UUID().uuidString
        try pairings.save(Pairing(clientKey: clientKey, certificateFingerprint: fingerprint, macAddresses: macAddresses), for: id)
        SavedTVs.save(SavedTVs.load() + [SavedTV(id: id, name: name, host: host, brand: kind)])

        if isDemo {
            listeners.values.forEach { $0.cancel() }
            listeners = [:]
            controllers = [:]
            tvs = []
            isDemo = false
        }
        let controller = Self.controller(for: client, macAddresses: macAddresses ?? [])
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

    /// Renames a TV in this app. A blank name keeps the old one.
    func renameTV(_ id: String, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        update(id) { $0.name = name }
        guard !isDemo else { return }
        SavedTVs.save(SavedTVs.load().map { saved in
            var saved = saved
            if saved.id == id { saved.name = name }
            return saved
        })
    }

    /// Forgets a paired TV. Removing the last one brings back the example TVs.
    func removeTV(_ id: String) {
        guard let client = clients.removeValue(forKey: id) else { return }
        Task { await client.disconnect() }
        listeners.removeValue(forKey: id)?.cancel()
        controllers[id] = nil
        pairings.remove(for: id)
        SavedTVs.save(SavedTVs.load().filter { $0.id != id })
        outputMemory[id] = nil
        OutputMemory.save(outputMemory.filter { key, _ in clients[key] != nil })
        pins[id] = nil
        installedApps[id] = nil
        PinnedApps.save(pins.filter { key, _ in clients[key] != nil })
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
            let stored = pairings.load(for: id)
            let key = try await client.connect(clientKey: stored?.clientKey)
            // Samsung can issue a new token; keep the latest so the TV doesn't ask again.
            if var pairing = stored, !key.isEmpty, key != pairing.clientKey {
                pairing.clientKey = key
                try? pairings.save(pairing, for: id)
            }
        } catch {
            if markOffOnFailure { update(id) { $0.isOn = false } }
            return false
        }
        update(id) { $0.isOn = true }
        let current = await backfillMACAddress(id, client: client) ?? controller
        await refresh(id, from: current)
        listen(to: id, current)
        return true
    }

    /// Pairing may have saved no MAC addresses (the TV didn't answer then), or, in older builds,
    /// only the wired one, which a TV on Wi‑Fi ignores. Ask again on each connect until both are known.
    /// Returns the new controller when the addresses were found.
    private func backfillMACAddress(_ id: String, client: any TVSession) async -> (any TVControlling)? {
        guard !(client is VizioClient), var pairing = pairings.load(for: id), pairing.macAddresses?.isEmpty ?? true else { return nil }
        let macAddresses = await Self.fetchMACAddresses(client)
        guard !macAddresses.isEmpty else { return nil }
        pairing.macAddresses = macAddresses
        try? pairings.save(pairing, for: id)
        let controller = Self.controller(for: client, macAddresses: macAddresses)
        controllers[id] = controller
        return controller
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
        if let points = try? await controller.launchPoints() { applyInstalled(points, to: id) }
        if let status = try? await controller.volume() {
            update(id) { tv in
                tv.volume = status.level
                tv.isMuted = status.muted
                if let output = status.soundOutput { tv.soundOutput = output }
            }
            if let output = status.soundOutput { rememberOutput(output, for: id) }
        }
        if let output = try? await controller.soundOutput() {
            update(id) { $0.soundOutput = output }
            rememberOutput(output, for: id)
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
            if !isDemo { rememberOutput(output, for: id) }
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
        var clients: [String: any TVSession] = [:]
        var controllers: [String: any TVControlling] = [:]
        for tv in saved {
            let pairing = pairings.load(for: tv.id)
            let client = session(tv.kind, host: tv.host, pairing: pairing)
            clients[tv.id] = client
            controllers[tv.id] = controller(for: client, macAddresses: pairing?.wakeAddresses ?? [])
        }
        let tvs = saved.map {
            TVState(id: $0.id, name: $0.name, isOn: false, volume: 0, isMuted: false, soundOutput: .tvSpeaker)
        }
        return RemoteStore(tvs: tvs, controllers: controllers, clients: clients)
    }

    // MARK: - Brands

    static func session(_ brand: TVBrand, host: String, pairing: Pairing?) -> any TVSession {
        switch brand {
        case .lg: return SSAPClient(host: host, pinnedFingerprint: pairing?.certificateFingerprint)
        case .samsung:
            // The token lets the app reconnect to wake a TV in standby without a new prompt.
            return SamsungClient(host: host, pinnedFingerprint: pairing?.certificateFingerprint, token: pairing?.clientKey)
        case .vizio: return VizioClient(host: host, pinnedFingerprint: pairing?.certificateFingerprint)
        }
    }

    /// For a typed address: Samsung and Vizio answer simple requests without pairing; anything else is LG.
    static func detectBrand(host: String) async -> TVBrand {
        async let samsung = SamsungDeviceInfo.fetch(host: host)
        async let vizio = VizioClient.probe(host: host)
        if await samsung != nil { return .samsung }
        if await vizio { return .vizio }
        return .lg
    }

    static func controller(for session: any TVSession, macAddresses: [String]) -> any TVControlling {
        if let samsung = session as? SamsungClient { return SamsungTV(client: samsung, macAddresses: macAddresses) }
        if let vizio = session as? VizioClient { return VizioTV(client: vizio) }
        return WebOSTV(client: session as! SSAPClient, macAddresses: macAddresses)
    }

    /// The addresses Wake-on-LAN needs. LG reports them once connected; Samsung on its info page.
    /// Vizio wakes with its power key instead.
    static func fetchMACAddresses(_ session: any TVSession) async -> [String] {
        if let lg = session as? SSAPClient {
            return (try? await WebOSTV(client: lg, macAddresses: []).fetchMACAddresses()) ?? []
        }
        if session is VizioClient { return [] }
        return [await SamsungDeviceInfo.fetch(host: session.host)?.wifiMAC].compactMap { $0 }
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
