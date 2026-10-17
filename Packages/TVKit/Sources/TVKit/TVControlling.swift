import Foundation

/// Everything the remote needs from a TV. `WebOSTV` talks to a real set; `MockTV` drives previews and the simulator.
public protocol TVControlling: Sendable {
    func volume() async throws -> VolumeStatus
    func setVolume(_ level: Int) async throws
    func setMute(_ muted: Bool) async throws
    func powerOn() async throws
    func powerOff() async throws
    func launchPoints() async throws -> [LaunchPoint]
    func launch(appID: String) async throws
    func foregroundAppID() async throws -> String?
    func soundOutput() async throws -> SoundOutput
    func setSoundOutput(_ output: SoundOutput) async throws
    /// Changes pushed by the TV: volume, sound output and the app on screen.
    func events() async -> AsyncStream<TVEvent>
}
