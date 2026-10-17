import Foundation
import Network

/// Turns a TV on by broadcasting a "magic packet" to its MAC address.
/// Needs "Turn on via Wi-Fi" (also called "Mobile TV On") enabled on the TV.
///
/// iOS only lets an app broadcast with the `com.apple.developer.networking.multicast`
/// entitlement, which has to be requested from Apple. See README.
public enum WakeOnLAN {
    /// 6 × 0xFF, then the MAC address 16 times.
    public static func magicPacket(macAddress: String) throws -> Data {
        let hex = macAddress.filter(\.isHexDigit)
        guard hex.count == 12 else { throw TVError.invalidMACAddress }
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { throw TVError.invalidMACAddress }
            bytes.append(byte)
            index = next
        }
        var packet = Data(repeating: 0xFF, count: 6)
        for _ in 0..<16 { packet.append(contentsOf: bytes) }
        return packet
    }

    public static func send(macAddress: String, broadcast: String = "255.255.255.255", port: UInt16 = 9) async throws {
        let packet = try magicPacket(macAddress: macAddress)
        guard let udpPort = NWEndpoint.Port(rawValue: port) else { throw TVError.invalidMACAddress }
        let connection = NWConnection(host: NWEndpoint.Host(broadcast), port: udpPort, using: .udp)
        let once = ResumeOnce()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: packet, completion: .contentProcessed { error in
                        connection.cancel()
                        once.run {
                            if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                        }
                    })
                case .failed(let error):
                    connection.cancel()
                    once.run { continuation.resume(throwing: error) }
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
        }
    }
}

/// Guards a continuation against being resumed twice by racing callbacks.
final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func run(_ body: () -> Void) {
        lock.lock()
        let first = !done
        done = true
        lock.unlock()
        if first { body() }
    }
}
