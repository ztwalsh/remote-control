import Foundation

/// Turns a TV on by broadcasting a "magic packet" to its MAC address.
/// Needs "Turn on via Wi-Fi" (also called "Mobile TV On") enabled on the TV.
///
/// iOS only lets an app broadcast with the `com.apple.developer.networking.multicast`
/// entitlement (granted for this app; see README).
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

    /// Broadcasts a packet for each address, to the general broadcast address and to each
    /// Wi‑Fi subnet's own (some routers drop the general one), on ports 9 and 7, a few times over:
    /// UDP can drop packets and the TV's network chip is half asleep.
    ///
    /// Uses BSD sockets: Network framework doesn't support broadcast (Apple DTS guidance).
    public static func send(macAddresses: [String], port: UInt16 = 9, repeats: Int = 3) async throws {
        let packets = try macAddresses.map(magicPacket(macAddress:))
        let targets = ["255.255.255.255"] + subnetBroadcastAddresses()
        var sentAny = false
        var lastError: Error?
        for attempt in 0..<repeats {
            if attempt > 0 { try await Task.sleep(for: .milliseconds(150)) }
            for packet in packets {
                for target in targets {
                    for port in [port, 7] {
                        do {
                            try sendOnce(packet, to: target, port: port)
                            sentAny = true
                        } catch {
                            lastError = error
                        }
                    }
                }
            }
        }
        if !sentAny, let lastError { throw lastError }
    }

    /// The broadcast address of each active IPv4 interface that supports broadcast, such as Wi‑Fi.
    static func subnetBroadcastAddresses() -> [String] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        var results: [String] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            let flags = Int32(entry.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_BROADCAST != 0, flags & IFF_LOOPBACK == 0,
                  let address = entry.ifa_dstaddr, address.pointee.sa_family == sa_family_t(AF_INET)
            else { continue }
            var host = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            let ok = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { inet -> Bool in
                var addr = inet.pointee.sin_addr
                return inet_ntop(AF_INET, &addr, &host, socklen_t(INET_ADDRSTRLEN)) != nil
            }
            let text = String(cString: host)
            if ok, !text.isEmpty, text != "0.0.0.0", !results.contains(text) { results.append(text) }
        }
        return results
    }

    private static func sendOnce(_ packet: Data, to broadcast: String, port: UInt16) throws {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { throw TVError.server("socket: \(String(cString: strerror(errno)))") }
        defer { close(fd) }

        var enable: Int32 = 1
        guard setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &enable, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            throw TVError.server("SO_BROADCAST: \(String(cString: strerror(errno)))")
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        guard inet_pton(AF_INET, broadcast, &address.sin_addr) == 1 else { throw TVError.invalidResponse }

        let sent = packet.withUnsafeBytes { bytes in
            withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, bytes.baseAddress, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent == packet.count else { throw TVError.server("sendto: \(String(cString: strerror(errno)))") }
    }
}
