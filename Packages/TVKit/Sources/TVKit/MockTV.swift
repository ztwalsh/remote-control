import Foundation

/// An in-memory TV for previews, the simulator and tests.
public actor MockTV: TVControlling {
    private var status: VolumeStatus
    private var output: SoundOutput
    private var foreground: String?
    private var isOn: Bool
    private var listeners: [UUID: AsyncStream<TVEvent>.Continuation] = [:]

    public init(volume: Int = 18, soundOutput: SoundOutput = .tvSpeaker, foregroundAppID: String? = nil, isOn: Bool = true) {
        status = VolumeStatus(level: volume, muted: false, soundOutput: soundOutput)
        output = soundOutput
        foreground = foregroundAppID
        self.isOn = isOn
    }

    public func volume() async throws -> VolumeStatus { status }

    public func setVolume(_ level: Int) async throws {
        status.level = min(100, max(0, level))
        status.muted = false
        emit(.volume(status))
    }

    public func setMute(_ muted: Bool) async throws {
        status.muted = muted
        emit(.volume(status))
    }

    public func powerOn() async throws { isOn = true }

    public func powerOff() async throws {
        isOn = false
        foreground = nil
        emit(.foregroundApp(nil))
    }

    public func launchPoints() async throws -> [LaunchPoint] { [] }

    public func launch(appID: String) async throws {
        foreground = appID
        emit(.foregroundApp(appID))
    }

    public func foregroundAppID() async throws -> String? { foreground }

    public func soundOutput() async throws -> SoundOutput { output }

    public func setSoundOutput(_ output: SoundOutput) async throws {
        self.output = output
        emit(.soundOutput(output))
    }

    public func press(_ button: RemoteButton) async throws {}

    public func events() async -> AsyncStream<TVEvent> {
        let (stream, continuation) = AsyncStream<TVEvent>.makeStream()
        let id = UUID()
        listeners[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeListener(id) }
        }
        return stream
    }

    private func removeListener(_ id: UUID) {
        listeners[id] = nil
    }

    private func emit(_ event: TVEvent) {
        listeners.values.forEach { $0.yield(event) }
    }
}
