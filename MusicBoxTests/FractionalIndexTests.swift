//
//  FractionalIndexTests.swift
//  MusicBox
//
//  Created by Max van Wezel on 06/05/2026.
//


import XCTest
@testable import MusicBox  // adjust to match your project

final class FractionalIndexTests: XCTestCase {

    // MARK: - Canonical test vectors (rocicorp test suite)

    func testCanonicalOkCases() throws {
        let cases: [(String?, String?, String)] = [
            (nil, nil, "a0"),
            (nil, "a0", "Zz"),
            (nil, "Zz", "Zy"),
            ("a0", nil, "a1"),
            ("a1", nil, "a2"),
            ("a0", "a1", "a0V"),
            ("a1", "a2", "a1V"),
            ("a0V", "a1", "a0l"),
            ("Zz", "a0", "ZzV"),
            ("Zz", "a1", "a0"),
            (nil, "Y00", "Xzzz"),
            ("bzz", nil, "c000"),
            ("a0", "a0V", "a0G"),
            ("a0", "a0G", "a08"),
            ("b125", "b129", "b127"),
            ("a0", "a1V", "a1"),
            ("Zz", "a01", "a0"),
            (nil, "a0V", "a0"),
            (nil, "b999", "b99"),
            (nil, "A000000000000000000000000001", "A000000000000000000000000000V"),
            ("zzzzzzzzzzzzzzzzzzzzzzzzzzy", nil, "zzzzzzzzzzzzzzzzzzzzzzzzzzz"),
            ("zzzzzzzzzzzzzzzzzzzzzzzzzzz", nil, "zzzzzzzzzzzzzzzzzzzzzzzzzzzV"),
        ]
        for (a, b, expected) in cases {
            let actual = try FractionalIndex.betweenThrowing(a, b)
            XCTAssertEqual(actual, expected, "between(\(String(describing: a)), \(String(describing: b)))")
        }
    }

    func testCanonicalErrorCases() {
        // smallest int sentinel
        assertThrowsError(a: nil, b: "A00000000000000000000000000")
        // trailing zero
        assertThrowsError(a: "a00", b: nil)
        assertThrowsError(a: "a00", b: "a1")
        // bad head character
        assertThrowsError(a: "0", b: "1")
        // a >= b
        assertThrowsError(a: "a1", b: "a0")
    }

    private func assertThrowsError(a: String?, b: String?, file: StaticString = #file, line: UInt = #line) {
        XCTAssertThrowsError(try FractionalIndex.betweenThrowing(a, b), file: file, line: line)
    }

    // MARK: - n-keys

    func testNKeysBase10() throws {
        let base10 = "0123456789"

        XCTAssertEqual(
            FractionalIndex.generateNKeysBetween(nil, nil, n: 5, digits: base10),
            ["a0", "a1", "a2", "a3", "a4"]
        )
        XCTAssertEqual(
            FractionalIndex.generateNKeysBetween("a4", nil, n: 10, digits: base10),
            ["a5", "a6", "a7", "a8", "a9", "b00", "b01", "b02", "b03", "b04"]
        )
        XCTAssertEqual(
            FractionalIndex.generateNKeysBetween(nil, "a0", n: 5, digits: base10),
            ["Z5", "Z6", "Z7", "Z8", "Z9"]
        )
        XCTAssertEqual(
            FractionalIndex.generateNKeysBetween("a0", "a2", n: 20, digits: base10),
            ["a01", "a02", "a03", "a035", "a04", "a05", "a06", "a07", "a08", "a09",
             "a1", "a11", "a12", "a13", "a14", "a15", "a16", "a17", "a18", "a19"]
        )
    }

    func testNKeysZeroAndOne() {
        XCTAssertEqual(FractionalIndex.generateNKeysBetween(nil, nil, n: 0), [])
        XCTAssertEqual(FractionalIndex.generateNKeysBetween(nil, nil, n: 1), ["a0"])
    }

    // MARK: - Validation

    func testValidateAcceptsValid() {
        for key in ["a0", "a0V", "Zz", "b00", "A000000000000000000000000001"] {
            XCTAssertTrue(FractionalIndex.isValid(key), "expected \(key) to be valid")
        }
    }

    func testValidateRejectsMalformed() {
        for key in ["", "zm", "foo", "a00", "A00000000000000000000000000", "a"] {
            XCTAssertFalse(FractionalIndex.isValid(key), "expected \(key) to be invalid")
        }
    }

    func testValidateRejectsOutsideAlphabet() {
        for key in ["a#?!@3124123", "a!", "a 1", "b1@"] {
            XCTAssertFalse(FractionalIndex.isValid(key), "expected \(key) to be invalid (alphabet)")
        }
    }

    func testValidateEnforcesMaxLength() {
        let longKey = "a" + String(repeating: "V", count: 200)
        XCTAssertFalse(FractionalIndex.isValid(longKey, maxLength: 50))
        XCTAssertFalse(FractionalIndex.isValid(longKey))  // default 100
    }

    // MARK: - Stability

    func testRandomInsertionsProduceValidSortedKeys() throws {
        var rng = SeededRNG(seed: 42)
        var keys: [String] = []
        // Seed with a few keys
        var prev: String? = nil
        for _ in 0..<5 {
            let k = FractionalIndex.between(prev, nil)
            keys.append(k)
            prev = k
        }
        // 1000 random insertions
        for _ in 0..<1000 {
            let n = keys.count
            let pos = Int(rng.next() % UInt64(n + 1))
            let a = pos > 0 ? keys[pos - 1] : nil
            let b = pos < n ? keys[pos] : nil
            let newKey = FractionalIndex.between(a, b)
            keys.insert(newKey, at: pos)
        }
        XCTAssertEqual(keys, keys.sorted(), "keys should remain sorted")
        XCTAssertEqual(keys.count, Set(keys).count, "all keys should be unique")
        for k in keys {
            XCTAssertTrue(FractionalIndex.isValid(k), "invalid key produced: \(k)")
        }
    }

    // Drop-in API: original signatures still work
    func testDropInAPI() {
        XCTAssertEqual(FractionalIndex.between(nil, nil), "a0")
        XCTAssertEqual(FractionalIndex.after(nil), "a0")
        XCTAssertEqual(FractionalIndex.after("a0"), "a1")
        XCTAssertEqual(FractionalIndex.before("a0"), "Zz")
    }
}

// Tiny seedable RNG for reproducible tests (xorshift64)
private struct SeededRNG {
    var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 1 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
