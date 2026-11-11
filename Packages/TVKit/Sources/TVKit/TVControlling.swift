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
    /// Sends a remote button: arrows, OK, Back, Home.
    func press(_ button: RemoteButton) async throws
    /// Changes pushed by the TV: volume, sound output and the app on screen.
    func events() async -> AsyncStream<TVEvent>
    var supportsSoundOutput: Bool { get }
}

public extension TVControlling {
    /// Whether the TV lets the app choose where its sound goes. LG does; Samsung doesn't.
    var supportsSoundOutput: Bool { true }
}

/// Who makes a TV, which decides how the app talks to it.
public enum TVBrand: String, Codable, Sendable {
    case lg, samsung, vizio

    public var displayName: String {
        switch self {
        case .lg: return "LG"
        case .samsung: return "Samsung"
        case .vizio: return "Vizio"
        }
    }
}

/// One connection to a TV, whatever its brand: connect (pairing the first time), disconnect,
/// and follow the connection state. `clientKey` is LG's client key, Samsung's token or Vizio's auth token.
public protocol TVSession: Sendable {
    var host: String { get }
    var states: AsyncStream<ConnectionState> { get }
    func connect(clientKey: String?) async throws -> String
    func disconnect() async
    var certificateFingerprint: String? { get async }
}

extension SSAPClient: TVSession {}
