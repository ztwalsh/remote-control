import Foundation

/// A real LG webOS TV, controlled over SSAP.
///
/// Not yet verified against hardware. Phase 0 of docs/PLAN.md checks each endpoint on real sets.
public final class WebOSTV: TVControlling {
    public let client: SSAPClient
    /// Needed for Wake-on-LAN, which is the only way to turn the TV on.
    public let macAddress: String?

    public init(client: SSAPClient, macAddress: String?) {
        self.client = client
        self.macAddress = macAddress
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
        guard let macAddress else { throw TVError.missingMACAddress }
        try await WakeOnLAN.send(macAddress: macAddress)
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

    /// Reads the MAC address while connected, so the TV can be woken later. Verify on hardware.
    public func fetchMACAddress() async throws -> String? {
        let info = try await client.request(SSAPURI.connectionInfo)
        return info["wiredInfo"]?["macAddress"]?.stringValue ?? info["wifiInfo"]?["macAddress"]?.stringValue
    }

    public func events() async -> AsyncStream<TVEvent> {
        let client = self.client
        let volumeUpdates = await client.subscribe(SSAPURI.getVolume)
        let outputUpdates = await client.subscribe(SSAPURI.getSoundOutput)
        let appUpdates = await client.subscribe(SSAPURI.foregroundApp)

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
            ]
            continuation.onTermination = { _ in tasks.forEach { $0.cancel() } }
        }
    }
}
