import Foundation

/// Lexicographic position strings for playlist item ordering. Phase 2 only needs `after(_:)` since
/// mutations are append-only; `before(_:)` and `between(_:_:)` land with reorder support.
nonisolated enum FractionalIndex {
    /// Returns a position string that sorts after `prev`. Pass `nil` to seed an empty playlist.
    static func after(_ prev: String?) -> String {
        guard let prev, !prev.isEmpty else { return "n" }
        let last = prev.last!
        if let ascii = last.asciiValue, ascii < Character("z").asciiValue! {
            let next = Character(UnicodeScalar(ascii + 1))
            return String(prev.dropLast()) + String(next)
        }
        return prev + "n"
    }
}
