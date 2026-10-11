import Foundation

/// Fractional indexing keys, byte-for-byte compatible with the
/// [rocicorp/fractional-indexing](https://github.com/rocicorp/fractional-indexing)
/// JS package and its Python/Elixir ports.
///
/// Keys are short, lexicographically-sortable strings used to maintain ordered
/// lists where items can be inserted between any two existing items without
/// renumbering.
///
/// ## Format
///
/// A key is `<integer part><optional fractional part>`:
///
/// - Integer part: a "head" character encodes its length. Lowercase `a..z`
///   represents positive integers (`a` = 1 trailing digit, `b` = 2, …, `z` = 26).
///   Uppercase `Z..A` represents the negative direction approaching zero
///   (`Z` = 1 trailing digit, `Y` = 2, …, `A` = 26).
/// - Fractional part: extra digits for arbitrary precision; must not end in `0`.
///
/// Default alphabet is base 62: `0-9A-Za-z`.
///
/// ## Public API
///
/// `between(_:_:)`, `after(_:)`, `before(_:)` are drop-in replacements for the
/// previous implementation; signatures are unchanged. They `fatalError` on
/// invalid input (matching the previous behavior).
///
/// New: `betweenThrowing(_:_:)` returns a `Result` for code paths that need
/// to handle malformed input (e.g. keys received over the network).
///
/// New: `isValid(_:)` and `validate(_:)` for input validation at API boundaries.
///
/// New: `generateNKeysBetween(_:_:n:)` for batch generation and rebalancing.
nonisolated enum FractionalIndex {

    // MARK: - Constants

    static let base62Digits = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
    static let defaultMaxLength = 100

    // MARK: - Errors

    enum FIError: Error, Equatable, CustomStringConvertible {
        case invalidOrderKey(String)
        case invalidIntegerPart(String)
        case invalidOrderKeyHead(Character)
        case invalidDigit(Character)
        case aGreaterOrEqualToB(String, String)
        case cannotIncrement
        case cannotDecrement
        case trailingZero
        case emptyKey
        case exceedsMaxLength(Int)
        case charactersOutsideAlphabet

        var description: String {
            switch self {
            case .invalidOrderKey(let k): return "invalid order key: \(k)"
            case .invalidIntegerPart(let k): return "invalid integer part of order key: \(k)"
            case .invalidOrderKeyHead(let c): return "invalid order key head: \(c)"
            case .invalidDigit(let c): return "invalid digit: \(c)"
            case .aGreaterOrEqualToB(let a, let b): return "\(a) >= \(b)"
            case .cannotIncrement: return "cannot increment any more"
            case .cannotDecrement: return "cannot decrement any more"
            case .trailingZero: return "trailing zero"
            case .emptyKey: return "empty order key"
            case .exceedsMaxLength(let n): return "order key exceeds max length of \(n)"
            case .charactersOutsideAlphabet: return "order key contains characters outside the digit alphabet"
            }
        }
    }

    // MARK: - Public API: drop-in replacements (non-throwing)

    /// Returns a key strictly between `a` and `b`. Pass nil for an unbounded side.
    /// Crashes on invalid input. Use `betweenThrowing` for error handling.
    static func between(_ a: String?, _ b: String?) -> String {
        between(a, b, digits: base62Digits)
    }

    /// Convenience — a key strictly greater than `prev`.
    static func after(_ prev: String?) -> String { between(prev, nil) }

    /// Convenience — a key strictly less than `next`.
    static func before(_ next: String?) -> String { between(nil, next) }

    static func between(_ a: String?, _ b: String?, digits: String) -> String {
        do {
            return try betweenThrowing(a, b, digits: digits)
        } catch {
            fatalError("FractionalIndex.between(\(a ?? "nil"), \(b ?? "nil")): \(error)")
        }
    }

    // MARK: - Public API: throwing variant

    /// Throwing version of `between(_:_:)`. Use this for code paths handling
    /// untrusted input (network, storage) where bad keys should be reported
    /// rather than crash the app.
    static func betweenThrowing(_ a: String?, _ b: String?, digits: String = base62Digits) throws -> String {
        if let a = a { try validateOrderKey(a, digits: digits) }
        if let b = b { try validateOrderKey(b, digits: digits) }
        if let a = a, let b = b, a >= b {
            throw FIError.aGreaterOrEqualToB(a, b)
        }
        return try generateKeyBetween(a, b, digits: digits)
    }

    // MARK: - Public API: validation

    /// Returns true if `key` is a structurally valid fractional index in the
    /// given alphabet, also checks that all characters are in the alphabet
    /// (stricter than the spec validator) and that the key is within max length.
    static func isValid(_ key: String, maxLength: Int = defaultMaxLength, digits: String = base62Digits) -> Bool {
        switch validate(key, maxLength: maxLength, digits: digits) {
        case .success: return true
        case .failure: return false
        }
    }

    /// Validates a key, returning a `Result` describing the outcome.
    static func validate(_ key: String, maxLength: Int = defaultMaxLength, digits: String = base62Digits) -> Result<
        Void, FIError
    > {
        if key.isEmpty {
            return .failure(.emptyKey)
        }
        if key.count > maxLength {
            return .failure(.exceedsMaxLength(maxLength))
        }
        // Character-set check first (stricter than spec validator).
        let digitSet = Set(digits)
        for ch in key {
            if !digitSet.contains(ch) {
                return .failure(.charactersOutsideAlphabet)
            }
        }
        do {
            try validateOrderKey(key, digits: digits)
            return .success(())
        } catch let e as FIError {
            return .failure(e)
        } catch {
            return .failure(.invalidOrderKey(key))
        }
    }

    // MARK: - Public API: batch / rebalance

    /// Returns `n` distinct keys strictly between `a` and `b`, in sorted order.
    /// Used for batch inserts and for rebalancing (call with `nil, nil, n`).
    static func generateNKeysBetween(_ a: String?, _ b: String?, n: Int, digits: String = base62Digits) -> [String] {
        do {
            return try generateNKeysBetweenThrowing(a, b, n: n, digits: digits)
        } catch {
            fatalError("FractionalIndex.generateNKeysBetween: \(error)")
        }
    }

    static func generateNKeysBetweenThrowing(_ a: String?, _ b: String?, n: Int, digits: String = base62Digits) throws
        -> [String]
    {
        if n == 0 { return [] }
        if n == 1 { return [try betweenThrowing(a, b, digits: digits)] }
        if b == nil {
            var c = try betweenThrowing(a, nil, digits: digits)
            var result = [c]
            for _ in 0..<(n - 1) {
                c = try betweenThrowing(c, nil, digits: digits)
                result.append(c)
            }
            return result
        }
        if a == nil {
            var c = try betweenThrowing(nil, b, digits: digits)
            var result = [c]
            for _ in 0..<(n - 1) {
                c = try betweenThrowing(nil, c, digits: digits)
                result.append(c)
            }
            return result.reversed()
        }
        let mid = n / 2
        let c = try betweenThrowing(a, b, digits: digits)
        let left = try generateNKeysBetweenThrowing(a, c, n: mid, digits: digits)
        let right = try generateNKeysBetweenThrowing(c, b, n: n - mid - 1, digits: digits)
        return left + [c] + right
    }

    // MARK: - Core algorithm

    private static func generateKeyBetween(_ a: String?, _ b: String?, digits: String) throws -> String {
        let zero = String(digits.first!)
        let smallestInt = "A" + String(repeating: zero, count: 26)

        if a == nil && b == nil {
            return "a" + zero
        }

        if a == nil {
            let b = b!
            let ib = try getIntegerPart(b)
            let fb = String(b.dropFirst(ib.count))
            if ib == smallestInt {
                return ib + (try midpoint("", fb, digits: digits))
            }
            if ib < b {
                return ib
            }
            guard let res = try decrementInteger(ib, digits: digits) else {
                throw FIError.cannotDecrement
            }
            return res
        }

        if b == nil {
            let a = a!
            let ia = try getIntegerPart(a)
            let fa = String(a.dropFirst(ia.count))
            if let i = try incrementInteger(ia, digits: digits) {
                return i
            }
            return ia + (try midpoint(fa, nil, digits: digits))
        }

        let a = a!
        let b = b!
        let ia = try getIntegerPart(a)
        let fa = String(a.dropFirst(ia.count))
        let ib = try getIntegerPart(b)
        let fb = String(b.dropFirst(ib.count))
        if ia == ib {
            return ia + (try midpoint(fa, fb, digits: digits))
        }
        guard let i = try incrementInteger(ia, digits: digits) else {
            throw FIError.cannotIncrement
        }
        if i < b {
            return i
        }
        return ia + (try midpoint(fa, nil, digits: digits))
    }

    // MARK: - Midpoint

    /// Both inputs are *fractional parts* (no integer prefix).
    /// `a` may be empty. `b` is nil or a non-empty string with `a < b`.
    /// No trailing zeros allowed.
    private static func midpoint(_ a: String, _ b: String?, digits: String) throws -> String {
        let zero = String(digits.first!)
        if let b = b, a >= b {
            throw FIError.aGreaterOrEqualToB(a, b)
        }
        if (a.last.map(String.init) == zero) || (b?.last.map(String.init) == zero) {
            throw FIError.trailingZero
        }
        return try midpointNoTrailingZero(a, b, digits: digits, zero: zero)
    }

    private static func midpointNoTrailingZero(_ a: String, _ b: String?, digits: String, zero: String) throws -> String
    {
        let n: Int
        if let b = b {
            n = commonPrefixLen(a, b, zero: zero)
        } else {
            n = 0
        }
        if n > 0 {
            return try midpointWithCommonPrefix(a, b!, digits: digits, n: n)
        }
        return try midpointAtFirstDiff(a, b, digits: digits)
    }

    private static func midpointWithCommonPrefix(_ a: String, _ b: String, digits: String, n: Int) throws -> String {
        let aRest = a.count > n ? String(a.dropFirst(n)) : ""
        let bRest = String(b.dropFirst(n))
        let prefix = String(b.prefix(n))
        return prefix + (try midpoint(aRest, bRest, digits: digits))
    }

    private static func midpointAtFirstDiff(_ a: String, _ b: String?, digits: String) throws -> String {
        let digitA: Int
        if a.isEmpty {
            digitA = 0
        } else {
            digitA = try digitIndex(digits, a.first!)
        }
        let digitB: Int
        if let b = b {
            digitB = try digitIndex(digits, b.first!)
        } else {
            digitB = digits.count
        }

        if digitB - digitA > 1 {
            let mid = roundHalfUpHalfSum(digitA, digitB)
            return String(digits[digits.index(digits.startIndex, offsetBy: mid)])
        }
        if let b = b, b.count > 1 {
            return String(b.first!)
        }
        // b is nil or length-1. Keep a's first digit, recurse.
        let aRest = a.count > 1 ? String(a.dropFirst(1)) : ""
        let firstDigit = String(digits[digits.index(digits.startIndex, offsetBy: digitA)])
        return firstDigit + (try midpoint(aRest, nil, digits: digits))
    }

    private static func commonPrefixLen(_ a: String, _ b: String, zero: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        let zeroChar = zero.first!
        var n = 0
        while n < bChars.count {
            let ac = n < aChars.count ? aChars[n] : zeroChar
            if ac == bChars[n] {
                n += 1
            } else {
                break
            }
        }
        return n
    }

    private static func roundHalfUpHalfSum(_ a: Int, _ b: Int) -> Int {
        let s = a + b
        return s % 2 == 0 ? s / 2 : (s + 1) / 2
    }

    private static func digitIndex(_ digits: String, _ ch: Character) throws -> Int {
        guard let idx = digits.firstIndex(of: ch) else {
            throw FIError.invalidDigit(ch)
        }
        return digits.distance(from: digits.startIndex, to: idx)
    }

    // MARK: - Integer part validation

    private static func validateOrderKey(_ key: String, digits: String) throws {
        if key.isEmpty {
            throw FIError.invalidOrderKey(key)
        }
        let zero = String(digits.first!)
        let smallest = "A" + String(repeating: zero, count: 26)
        if key == smallest {
            throw FIError.invalidOrderKey(key)
        }
        let i = try getIntegerPart(key)
        let f = String(key.dropFirst(i.count))
        if !f.isEmpty, String(f.last!) == zero {
            throw FIError.invalidOrderKey(key)
        }
    }

    private static func getIntegerPart(_ key: String) throws -> String {
        guard let head = key.first else {
            throw FIError.invalidOrderKey(key)
        }
        let n = try getIntegerLength(head)
        if n > key.count {
            throw FIError.invalidOrderKey(key)
        }
        return String(key.prefix(n))
    }

    private static func getIntegerLength(_ head: Character) throws -> Int {
        if let ascii = head.asciiValue {
            if ascii >= UInt8(ascii: "a") && ascii <= UInt8(ascii: "z") {
                return Int(ascii) - Int(UInt8(ascii: "a")) + 2
            }
            if ascii >= UInt8(ascii: "A") && ascii <= UInt8(ascii: "Z") {
                return Int(UInt8(ascii: "Z")) - Int(ascii) + 2
            }
        }
        throw FIError.invalidOrderKeyHead(head)
    }

    private static func validateInteger(_ i: String) throws {
        guard let head = i.first else {
            throw FIError.invalidIntegerPart(i)
        }
        let expected = try getIntegerLength(head)
        if expected != i.count {
            throw FIError.invalidIntegerPart(i)
        }
    }

    // MARK: - Increment / decrement integer parts

    /// Returns next integer part, or nil if at "z" overflow (caller adds fractional).
    private static func incrementInteger(_ x: String, digits: String) throws -> String? {
        try validateInteger(x)
        let zero = String(digits.first!)
        let head = String(x.first!)
        var digs = Array(x.dropFirst()).map { String($0) }

        var i = digs.count - 1
        var carry = true
        while carry && i >= 0 {
            let idx = try digitIndex(digits, digs[i].first!)
            if idx + 1 == digits.count {
                digs[i] = zero
                i -= 1
            } else {
                let newCh = digits[digits.index(digits.startIndex, offsetBy: idx + 1)]
                digs[i] = String(newCh)
                carry = false
            }
        }
        if !carry {
            return head + digs.joined()
        }
        return promoteHeadForward(head: head, digs: digs, zero: zero)
    }

    private static func promoteHeadForward(head: String, digs: [String], zero: String) -> String? {
        if head == "Z" { return "a" + zero }
        if head == "z" { return nil }
        let c = head.unicodeScalars.first!.value
        let newHead = String(UnicodeScalar(c + 1)!)
        if newHead > "a" {
            // crossed into longer-length lowercase territory: append a zero
            return newHead + digs.joined() + zero
        }
        // crossing within uppercase toward 'a': drop the last digit
        return newHead + digs.dropLast().joined()
    }

    /// Returns previous integer part, or nil if at "A" overflow.
    private static func decrementInteger(_ x: String, digits: String) throws -> String? {
        try validateInteger(x)
        let last = String(digits.last!)
        let head = String(x.first!)
        var digs = Array(x.dropFirst()).map { String($0) }

        var i = digs.count - 1
        var borrow = true
        while borrow && i >= 0 {
            let idx = try digitIndex(digits, digs[i].first!)
            if idx == 0 {
                digs[i] = last
                i -= 1
            } else {
                let newCh = digits[digits.index(digits.startIndex, offsetBy: idx - 1)]
                digs[i] = String(newCh)
                borrow = false
            }
        }
        if !borrow {
            return head + digs.joined()
        }
        return promoteHeadBackward(head: head, digs: digs, last: last)
    }

    private static func promoteHeadBackward(head: String, digs: [String], last: String) -> String? {
        if head == "a" { return "Z" + last }
        if head == "A" { return nil }
        let c = head.unicodeScalars.first!.value
        let newHead = String(UnicodeScalar(c - 1)!)
        if newHead < "Z" {
            return newHead + digs.joined() + last
        }
        return newHead + digs.dropLast().joined()
    }
}
