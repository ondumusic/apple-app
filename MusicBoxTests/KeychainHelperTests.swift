import Foundation
import Testing
@testable import MusicBox

struct KeychainHelperTests {

    /// Unique key prefix per test run to avoid collisions with real data.
    private let prefix = "test_\(UUID().uuidString)_"

    private func key(_ name: String) -> String { prefix + name }

    // MARK: - Save & Load

    @Test func saveAndLoad() {
        let k = key("token")
        defer { KeychainHelper.delete(key: k) }

        KeychainHelper.save("secret123", for: k)
        #expect(KeychainHelper.load(key: k) == "secret123")
    }

    @Test func saveOverwritesPreviousValue() {
        let k = key("token")
        defer { KeychainHelper.delete(key: k) }

        KeychainHelper.save("first", for: k)
        KeychainHelper.save("second", for: k)
        #expect(KeychainHelper.load(key: k) == "second")
    }

    @Test func loadMissingKeyReturnsNil() {
        #expect(KeychainHelper.load(key: key("nonexistent")) == nil)
    }

    // MARK: - Delete

    @Test func deleteSingleKey() {
        let k = key("token")
        KeychainHelper.save("value", for: k)
        KeychainHelper.delete(key: k)
        #expect(KeychainHelper.load(key: k) == nil)
    }

    @Test func deleteNonexistentKeyDoesNotCrash() {
        KeychainHelper.delete(key: key("nope"))
    }

    // MARK: - Unicode & special values

    @Test func unicodeValue() {
        let k = key("unicode")
        defer { KeychainHelper.delete(key: k) }

        let value = "こんにちは🎵"
        KeychainHelper.save(value, for: k)
        #expect(KeychainHelper.load(key: k) == value)
    }

    @Test func emptyStringValue() {
        let k = key("empty")
        defer { KeychainHelper.delete(key: k) }

        KeychainHelper.save("", for: k)
        #expect(KeychainHelper.load(key: k) == "")
    }
}
