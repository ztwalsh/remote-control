import Foundation

/// A paired TV the app remembers between launches. Its client key and certificate fingerprint
/// live in the Keychain (`PairingStore`), under the same `id`.
struct SavedTV: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var host: String
}

/// The list of paired TVs, kept in UserDefaults. Nothing secret is stored here.
enum SavedTVs {
    private static let key = "savedTVs"

    static func load() -> [SavedTV] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([SavedTV].self, from: data)) ?? []
    }

    static func save(_ tvs: [SavedTV]) {
        guard let data = try? JSONEncoder().encode(tvs) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
