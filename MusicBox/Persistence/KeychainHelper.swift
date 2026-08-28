import Foundation
import Security

nonisolated enum KeychainHelper {
    private static let service = "com.example.MusicBox"

    private static func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    static func save(_ value: String, for key: String) {
        guard let data = value.data(using: .utf8) else { return }

        // Delete any existing item first
        SecItemDelete(baseQuery(for: key) as CFDictionary)

        var query = baseQuery(for: key)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    /// Distinguishes "nothing stored" from "the read failed". Collapsing the two sends a
    /// user with a perfectly good stored session to the login screen with no explanation —
    /// a denied access prompt and a fresh install look identical otherwise.
    enum LoadOutcome {
        case found(String)
        case missing
        case failed(OSStatus)
    }

    static func loadOutcome(key: String) -> LoadOutcome {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
                return .failed(errSecDecode)
            }
            return .found(value)
        case errSecItemNotFound:
            return .missing
        default:
            return .failed(status)
        }
    }

    static func load(key: String) -> String? {
        if case .found(let value) = loadOutcome(key: key) { return value }
        return nil
    }

    static func delete(key: String) {
        SecItemDelete(baseQuery(for: key) as CFDictionary)
    }

    static func deleteAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
