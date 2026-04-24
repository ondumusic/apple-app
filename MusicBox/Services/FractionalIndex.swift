import Foundation

/// Lexicographic position strings over the lowercase a-z alphabet. Any new position is computed
/// as a midpoint (or an extension when the midpoint isn't a valid single char), so positions
/// grow in length only when the surrounding neighbors are already adjacent.
nonisolated enum FractionalIndex {
    private static let firstChar: UInt8 = 0x61  // 'a' = 97
    private static let lastChar: UInt8  = 0x7A  // 'z' = 122
    // Virtual sentinels for "no lower bound" / "no upper bound".
    private static let loBound = Int(firstChar) - 1  // 96
    private static let hiBound = Int(lastChar) + 1   // 123

    /// Returns a string strictly between `a` and `b`. Pass nil for an unbounded side.
    /// Preconditions: if both non-nil, `a < b` lexicographically.
    static func between(_ a: String?, _ b: String?) -> String {
        let aChars = Array((a ?? "").utf8)
        let bChars = b.map { Array($0.utf8) }

        // Walk common prefix.
        var i = 0
        while i < aChars.count,
              let bc = bChars, i < bc.count,
              aChars[i] == bc[i] {
            i += 1
        }

        let prefix = String(decoding: aChars.prefix(i), as: UTF8.self)
        let lo: Int = i < aChars.count ? Int(aChars[i]) : loBound
        let hi: Int
        if let bc = bChars {
            hi = i < bc.count ? Int(bc[i]) : hiBound
        } else {
            hi = hiBound
        }

        // Midpoint character fits strictly between.
        if hi - lo > 1 {
            let mid = (lo + hi) / 2
            return prefix + String(Character(UnicodeScalar(UInt8(mid))))
        }

        // Adjacent (hi == lo + 1). Extend into a's suffix if lo is real, otherwise into b's.
        if lo >= Int(firstChar) {
            let loStr = String(Character(UnicodeScalar(UInt8(lo))))
            let aSuffix = aChars.count > i + 1 ? String(decoding: aChars[(i+1)...], as: UTF8.self) : nil
            return prefix + loStr + between(aSuffix, nil)
        } else {
            // a ended (lo is sentinel). b's char at i must be 'a' (since hi = 97). Keep it,
            // recurse into the remainder of b on the upper side.
            let bSuffix: String? = {
                guard let bc = bChars, bc.count > i + 1 else { return nil }
                return String(decoding: bc[(i+1)...], as: UTF8.self)
            }()
            return prefix + "a" + between(nil, bSuffix)
        }
    }

    /// Convenience — a string > `prev`.
    static func after(_ prev: String?) -> String { between(prev, nil) }

    /// Convenience — a string < `next`.
    static func before(_ next: String?) -> String { between(nil, next) }
}
