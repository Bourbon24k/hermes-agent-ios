import Foundation
import Security

/// Persisted relay session (tokens + base URL), stored in the Keychain.
struct RelaySession: Codable {
    var relayBaseURL: String        // ends with /v1
    var userId: String
    var displayName: String
    var deviceId: String
    var accessToken: String
    var refreshToken: String
    var accessExpiresAt: Date?
    var installationId: String
}

enum RelaySessionStore {
    private static let service = "me.clawpilot.hermes-agent.relay-session"
    private static let account = "default"

    static func load() -> RelaySession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return try? JSONDecoder().decode(RelaySession.self, from: data)
    }

    static func save(_ session: RelaySession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        var query = baseQuery
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    static func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// Stable per-install identifier reused across pairings.
    static var installationId: String {
        let key = "hermes.relay.installationId"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: key)
        return generated
    }
}
