import Foundation

/// A real LG webOS TV, controlled over SSAP.
///
/// Not yet verified against hardware. Phase 0 of docs/PLAN.md checks each endpoint on real sets.
public final class WebOSTV: TVControlling {
    public let client: SSAPClient
    /// Needed for Wake-on-LAN, which is the only way to turn the TV on.
    public let macAddresses: [String]
    private let pointer: PointerInput

    public init(client: SSAPClient, macAddresses: [String]) {
        self.client = client
        self.macAddresses = macAddresses
        pointer = PointerInput(client: client)
    }

    public func volume() async throws -> VolumeStatus {
        guard let status = VolumeStatus.parse(try await client.request(SSAPURI.getVolume)) else {
            throw TVError.invalidResponse
        }
        return status
    }

    public func setVolume(_ level: Int) async throws {
        _ = try await client.request(SSAPURI.setVolume, payload: ["volume": .number(Double(min(100, max(0, level))))])
    }

    public func setMute(_ muted: Bool) async throws {
        _ = try await client.request(SSAPURI.setMute, payload: ["mute": .bool(muted)])
    }

    public func powerOn() async throws {
        guard !macAddresses.isEmpty else { throw TVError.missingMACAddress }
        try await WakeOnLAN.send(macAddresses: macAddresses)
    }

    public func powerOff() async throws {
        _ = try await client.request(SSAPURI.turnOff)
    }

    public func launchPoints() async throws -> [LaunchPoint] {
        LaunchPoint.parseList(try await client.request(SSAPURI.listLaunchPoints))
    }

    public func launch(appID: String) async throws {
        _ = try await client.request(SSAPURI.launch, payload: ["id": .string(appID)])
    }

    public func foregroundAppID() async throws -> String? {
        try await client.request(SSAPURI.foregroundApp)["appId"]?.stringValue
    }

    public func soundOutput() async throws -> SoundOutput {
        guard let raw = try await client.request(SSAPURI.getSoundOutput)["soundOutput"]?.stringValue else {
            throw TVError.invalidResponse
        }
        return SoundOutput(rawValue: raw)
    }

    public func setSoundOutput(_ output: SoundOutput) async throws {
        _ = try await client.request(SSAPURI.changeSoundOutput, payload: ["output": .string(output.rawValue)])
    }

    /// Reads the MAC addresses while connected, so the TV can be woken later.
    ///
    /// The TV reports both its Wi‑Fi and Ethernet addresses whether or not a cable is plugged in,
    /// and only the one it's connected with wakes it, so keep both (Wi‑Fi first).
    public func fetchMACAddresses() async throws -> [String] {
        let info = try await client.request(SSAPURI.connectionInfo)
        return Self.macAddresses(in: info)
    }

    /// Reads the play state from a media update: true when paused, false when playing, nil when
    /// the TV doesn't say (nothing playing, or a state like "loaded").
    static func isPaused(in payload: JSONValue) -> Bool? {
        for item in payload["foregroundAppInfo"]?.arrayValue ?? [] {
            switch item["playState"]?.stringValue {
            case "playing": return false
            case "paused": return true
            default: continue
            }
        }
        return nil
    }

    static func macAddresses(in info: JSONValue) -> [String] {
        var seen: [String] = []
        for key in ["wifiInfo", "wiredInfo"] {
            guard let raw = info[key]?["macAddress"]?.stringValue,
                  (try? WakeOnLAN.magicPacket(macAddress: raw)) != nil,
                  !seen.contains(where: { $0.caseInsensitiveCompare(raw) == .orderedSame })
            else { continue }
            seen.append(raw)
        }
        return seen
    }

    // MARK: - Buttons

    public func press(_ button: RemoteButton) async throws { try await pointer.press(button) }

    // MARK: - Keyboard

    public var supportsKeyboard: Bool { true }

    /// LG types at the cursor, so this deletes back to where the texts differ and types the rest.
    public func replaceText(_ old: String, with new: String) async throws {
        let edit = TextEdit(from: old, to: new)
        if edit.deleteCount > 0 {
            _ = try await client.request(SSAPURI.deleteCharacters, payload: ["count": .number(Double(edit.deleteCount))])
        }
        if !edit.insert.isEmpty {
            _ = try await client.request(SSAPURI.insertText, payload: ["text": .string(edit.insert), "replace": .number(0)])
        }
    }

    public func submitText() async throws {
        _ = try await client.request(SSAPURI.sendEnterKey)
    }

    public func events() async -> AsyncStream<TVEvent> {
        let client = self.client
        let volumeUpdates = await client.subscribe(SSAPURI.getVolume)
        let outputUpdates = await client.subscribe(SSAPURI.getSoundOutput)
        let appUpdates = await client.subscribe(SSAPURI.foregroundApp)
        let keyboardUpdates = await client.subscribe(SSAPURI.remoteKeyboard)
        let mediaUpdates = await client.subscribe(SSAPURI.mediaState)

        return AsyncStream { continuation in
            let tasks = [
                Task {
                    do {
                        for try await payload in volumeUpdates {
                            if let status = VolumeStatus.parse(payload) { continuation.yield(.volume(status)) }
                        }
                    } catch {
                        continuation.yield(.disconnected)
                    }
                },
                Task {
                    // Older sets don't support this subscription; the remote still works without it.
                    do {
                        for try await payload in outputUpdates {
                            if let raw = payload["soundOutput"]?.stringValue {
                                continuation.yield(.soundOutput(SoundOutput(rawValue: raw)))
                            }
                        }
                    } catch {}
                },
                Task {
                    do {
                        for try await payload in appUpdates {
                            continuation.yield(.foregroundApp(payload["appId"]?.stringValue))
                        }
                    } catch {}
                },
                Task {
                    // Older sets and some apps don't report this; play and pause then fall back to a guess.
                    do {
                        for try await payload in mediaUpdates {
                            if let paused = Self.isPaused(in: payload) { continuation.yield(.paused(paused)) }
                        }
                    } catch {}
                },
                Task {
                    // Needs the text input permission; TVs paired before it was added refuse it.
                    do {
                        for try await payload in keyboardUpdates {
                            if let focus = payload["currentWidget"]?["focus"]?.boolValue {
                                continuation.yield(.keyboard(focus))
                            }
                        }
                    } catch {}
                },
            ]
            continuation.onTermination = { _ in tasks.forEach { $0.cancel() } }
        }
    }
}
