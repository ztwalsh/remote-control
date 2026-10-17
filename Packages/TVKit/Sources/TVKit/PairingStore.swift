import Foundation
import Security

/// What's kept after pairing with a TV: the client key the TV issued and its certificate fingerprint.
public struct Pairing: Codable, Sendable, Equatable {
    public var clientKey: String
    public var certificateFingerprint: String?
    public var macAddress: String?

    public init(clientKey: String, certificateFingerprint: String?, macAddress: String?) {
        self.clientKey = clientKey
        self.certificateFingerprint = certificateFingerprint
        self.macAddress = macAddress
    }
}

/// Stores pairings in the Keychain, one item per TV.
public struct PairingStore: Sendable {
    private let service: String

    public init(service: String = "RemoteControl.pairing") {
        self.service = service
    }

    public func save(_ pairing: Pairing, for tvID: String) throws {
        let data = try JSONEncoder().encode(pairing)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tvID,
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw TVError.server("Keychain error \(status)") }
    }

    public func load(for tvID: String) -> Pairing? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tvID,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(Pairing.self, from: data)
    }

    public func remove(for tvID: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tvID,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
