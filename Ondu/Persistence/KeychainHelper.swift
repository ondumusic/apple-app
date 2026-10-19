import Foundation
import Security

nonisolated enum KeychainHelper {
    /// The bundle identifier, so Debug and release builds keep separate logins the way
    /// they keep separate containers, and a rename can't leave it naming an old app.
    private static let service = Bundle.main.bundleIdentifier ?? "Ondu"

    #if os(macOS)
    /// macOS has two keychains. The file-based one ties an item to the exact code signature
    /// of the build that saved it: a build signed differently is prompted to read it and
    /// refused changing it, so a rebuild could keep reading a token it could no longer
    /// replace — an expired session on every launch. The data protection keychain, the
    /// only one iOS has, goes by team and bundle identifier instead. It needs a team-signed
    /// build; an ad hoc one is refused with errSecMissingEntitlement and keeps the
    /// file-based keychain.
    ///
    /// Probed with a delete of an item that never exists, not a read: for an ad hoc build a
    /// read comes back as not found, as if the keychain were usable, and only writes are
    /// refused — so a read probe chose a keychain every save then failed against.
    private static let usesDataProtectionKeychain: Bool = {
        let probe: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "data-protection-probe",
            kSecUseDataProtectionKeychain as String: true,
        ]
        let usable = SecItemDelete(probe as CFDictionary) != errSecMissingEntitlement
        #if DEBUG
        if !usable { print("KeychainHelper: build isn't team-signed; using the file-based keychain") }
        #endif
        return usable
    }()
    #endif

    private static var serviceQuery: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        #if os(macOS)
        if usesDataProtectionKeychain {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        #endif
        return query
    }

    private static func baseQuery(for key: String) -> [String: Any] {
        var query = serviceQuery
        query[kSecAttrAccount as String] = key
        return query
    }

    /// Readable from the first unlock on, so background downloads can still authenticate,
    /// but never carried in a backup to another device: the token signs in as the user,
    /// and a new device signing in again costs only a password.
    private static let accessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    /// Updates in place rather than deleting and re-adding, and doesn't ignore the result:
    /// deleting first and ignoring both results is how a refused save left the old token
    /// behind with nothing to show for it.
    static func save(_ value: String, for key: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query = baseQuery(for: key)

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessibility,
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item.merge(attributes) { _, new in new }
            status = SecItemAdd(item as CFDictionary, nil)
        }
        #if DEBUG
        if status != errSecSuccess {
            let reason = SecCopyErrorMessageString(status, nil).map { $0 as String } ?? ""
            print("KeychainHelper: saving \(key) failed with OSStatus \(status) \(reason)")
        }
        #endif
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
        SecItemDelete(serviceQuery as CFDictionary)
    }
}
