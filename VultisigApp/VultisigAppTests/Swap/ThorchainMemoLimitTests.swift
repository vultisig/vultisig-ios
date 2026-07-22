//
//  ThorchainMemoLimitTests.swift
//  VultisigAppTests
//
//  Coverage for `ThorchainMemoLimit.compressed(_:maxBytes:)` (round-DOWN LIM
//  compression into scientific notation) and `memoByteLimit(for:)`. The
//  load-bearing invariants: the compressed floor is always <= the original and
//  > 0 (round-down), every non-LIM field is byte-identical, and no-op cases
//  return the memo unchanged.
//

import BigInt
import XCTest
@testable import VultisigApp

final class ThorchainMemoLimitTests: XCTestCase {

    // The real boundary example from the live thornode test: exactly 80 bytes,
    // a 14-digit LIM. `=:ASSET:DEST:LIM/INTERVAL/QUANTITY:AFFILIATE:FEE`.
    private let boundaryMemo = "=:ETH.USDC:0x742d35Cc6634C0532925a3b844Bc454e4438f44e:65342292972125/0/224:vi:50"
    // The ≥20 BTC overflow: same shape with a 15-digit LIM → 81 bytes → thornode
    // rejects "generated memo too long for source chain" without compression.
    private let overflowMemo = "=:ETH.USDC:0x742d35Cc6634C0532925a3b844Bc454e4438f44e:653422929721250/0/224:vi:50"

    // MARK: - Compression happens (round-down, fits, sci-notation)

    func testCompressesOverflowingLimToScientificNotation() {
        XCTAssertEqual(overflowMemo.utf8.count, 81, "Precondition: overflow memo is 81 bytes")
        let result = ThorchainMemoLimit.compressed(overflowMemo, maxBytes: 80)

        XCTAssertNotEqual(result, overflowMemo, "An overflowing memo must be compressed")
        XCTAssertLessThanOrEqual(result.utf8.count, 80, "Compressed memo must fit the 80-byte cap")
        XCTAssertTrue(limField(of: result).contains("e"), "LIM must be scientific notation")

        let original = BigInt("653422929721250")
        let compressed = decodedLim(from: result)
        XCTAssertNotNil(compressed)
        XCTAssertLessThan(compressed!, original, "Round-down: compressed floor is strictly lower")
        XCTAssertGreaterThan(compressed!, 0, "Floor must stay positive")
    }

    // Honours the task's explicit 14-digit LIM value. The boundary memo is
    // exactly 80 bytes, so it overflows only a tighter cap; at 79 the same
    // `65342292972125` LIM compresses to sci-notation, rounding down.
    func testCompressesFourteenDigitTaskLimWhenOverCap() {
        let result = ThorchainMemoLimit.compressed(boundaryMemo, maxBytes: 79)

        XCTAssertNotEqual(result, boundaryMemo)
        XCTAssertLessThanOrEqual(result.utf8.count, 79)
        XCTAssertTrue(limField(of: result).contains("e"))

        let original = BigInt("65342292972125")
        let compressed = decodedLim(from: result)!
        XCTAssertLessThan(compressed, original, "Round-down invariant")
        XCTAssertGreaterThan(compressed, 0)
    }

    // Task boundary example: exactly 80 bytes at an 80-byte cap → it fits, so it
    // is a byte-identical no-op that stays a valid `=:…:<lim>/0/224:vi:50` shape.
    func testBoundaryMemoAtEightyByteCapIsNoOp() {
        XCTAssertEqual(boundaryMemo.utf8.count, 80, "Precondition: boundary memo is 80 bytes")
        let result = ThorchainMemoLimit.compressed(boundaryMemo, maxBytes: 80)

        XCTAssertEqual(result, boundaryMemo, "A memo that already fits is left untouched")
        XCTAssertLessThanOrEqual(result.utf8.count, 80)
        let fields = result.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        XCTAssertEqual(fields.first, "=")
        XCTAssertTrue(fields[3].hasSuffix("/0/224"))
        XCTAssertEqual(fields[4], "vi")
        XCTAssertEqual(fields[5], "50")
    }

    // MARK: - No-ops

    func testNoOpWhenMemoAlreadyFits() {
        let memo = "=:ETH.USDC:0xAbCd:1000/0/0:vi:50"
        XCTAssertLessThanOrEqual(memo.utf8.count, 80)
        XCTAssertEqual(ThorchainMemoLimit.compressed(memo, maxBytes: 80), memo)
    }

    func testNoOpWhenLimIsZero() {
        // No floor: even if forced past the cap, a "0" LIM has nothing to
        // compress and must be returned untouched.
        let memo = "=:ETH.USDC:0x742d35Cc6634C0532925a3b844Bc454e4438f44e:0/0/224:vi:50"
        XCTAssertEqual(ThorchainMemoLimit.compressed(memo, maxBytes: 10), memo)
    }

    func testNoOpWhenMaxBytesIsNil() {
        XCTAssertEqual(ThorchainMemoLimit.compressed(overflowMemo, maxBytes: nil), overflowMemo)
    }

    // MARK: - Non-LIM fields are byte-identical

    func testNonLimFieldsAreByteIdentical() {
        let result = ThorchainMemoLimit.compressed(overflowMemo, maxBytes: 80)
        let before = overflowMemo.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        let after = result.split(separator: ":", omittingEmptySubsequences: false).map(String.init)

        XCTAssertEqual(before.count, after.count)
        // Function, asset, destination, affiliate, fee: verbatim.
        XCTAssertEqual(after[0], before[0])
        XCTAssertEqual(after[1], before[1])
        XCTAssertEqual(after[2], before[2])
        XCTAssertEqual(after[4], before[4])
        XCTAssertEqual(after[5], before[5])
        // Only the LIM before the first `/` changed; the streaming suffix is kept.
        XCTAssertTrue(before[3].hasSuffix("/0/224"))
        XCTAssertTrue(after[3].hasSuffix("/0/224"))
        XCTAssertNotEqual(limField(of: result), limField(of: overflowMemo))
    }

    // MARK: - Malformed / unexpected memos

    func testMalformedMemosReturnedUnchanged() {
        // Small cap forces each input past the fits-check so the shape/LIM
        // guards are the reason it is returned unchanged.
        let cases = [
            "=:ETH.USDC:0xabc",                        // fewer than 4 fields
            "=:ETH.USDC:0xabc:notanumber/0/0:vi:50",   // LIM not an integer
            "=:ETH.USDC:0xabc:65342e9/0/0:vi:50",      // LIM already scientific
            "=:ETH.USDC:0xabc:007/0/0:vi:50",          // zero-padded (non-canonical)
            "=:ETH.USDC:0xabc:-5/0/0:vi:50"            // negative
        ]
        for memo in cases {
            XCTAssertEqual(ThorchainMemoLimit.compressed(memo, maxBytes: 5), memo, "Unchanged for: \(memo)")
        }
    }

    // MARK: - Maya

    func testMayaFormatMemoCompressesSameWay() {
        // Maya is a THORChain fork with the same memo grammar and also parses
        // scientific notation. 83 bytes → must compress to fit 80.
        let maya = "=:THOR.RUNE:maya1qz8p9dxq4l7wg2m4vtn5xq6r3jf0h8u2vk9c7d:653422929721250/0/224:vi:50"
        XCTAssertEqual(maya.utf8.count, 83)
        let result = ThorchainMemoLimit.compressed(maya, maxBytes: 80)

        XCTAssertNotEqual(result, maya)
        XCTAssertLessThanOrEqual(result.utf8.count, 80)
        XCTAssertTrue(limField(of: result).contains("e"))
        let compressed = decodedLim(from: result)!
        XCTAssertLessThan(compressed, BigInt("653422929721250"))
        XCTAssertGreaterThan(compressed, 0)
        // Destination and affiliate untouched.
        let fields = result.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        XCTAssertEqual(fields[2], "maya1qz8p9dxq4l7wg2m4vtn5xq6r3jf0h8u2vk9c7d")
        XCTAssertEqual(fields[4], "vi")
    }

    // MARK: - Round-down invariant across magnitudes

    func testRoundDownInvariantAcrossMagnitudes() {
        let lims = ["100000007", "999999999999", "65342292972125", "653422929721250", "123456789012345678", "900000000000001"]
        for lim in lims {
            let memo = "=:ETH.USDC:0x742d35Cc6634C0532925a3b844Bc454e4438f44e:\(lim)/0/224:vi:50"
            // One byte under the exact length forces minimal compression.
            let cap = memo.utf8.count - 1
            let result = ThorchainMemoLimit.compressed(memo, maxBytes: cap)

            XCTAssertLessThanOrEqual(result.utf8.count, cap, "Must fit cap for LIM \(lim)")
            XCTAssertTrue(limField(of: result).contains("e"), "Must be sci-notation for LIM \(lim)")
            let original = BigInt(lim)!
            let compressed = decodedLim(from: result)!
            XCTAssertLessThanOrEqual(compressed, original, "Round-down for LIM \(lim)")
            XCTAssertGreaterThan(compressed, 0, "Positive floor for LIM \(lim)")
        }
    }

    // MARK: - memoByteLimit

    func testMemoByteLimitIsEightyForUtxoSourcesAndNilOtherwise() {
        for chain in [Chain.bitcoin, .litecoin, .bitcoinCash, .dogecoin, .dash, .zcash] {
            XCTAssertEqual(ThorchainMemoLimit.memoByteLimit(for: chain), 80, "\(chain) is a UTXO OP_RETURN source")
        }
        for chain in [Chain.ethereum, .thorChain, .gaiaChain, .mayaChain, .solana, .cardano] {
            XCTAssertNil(ThorchainMemoLimit.memoByteLimit(for: chain), "\(chain) carries no 80-byte OP_RETURN cap")
        }
    }

    // MARK: - Helpers

    /// The LIM substring of field index 3 (before the first `/`).
    private func limField(of memo: String) -> String {
        let fields = memo.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard fields.count > 3 else { return "" }
        return fields[3].split(separator: "/", omittingEmptySubsequences: false).first.map(String.init) ?? fields[3]
    }

    /// Decodes a plain or `<mantissa>e<exponent>` LIM into its integer value.
    private func decodedLim(from memo: String) -> BigInt? {
        let field = limField(of: memo)
        guard let eIndex = field.firstIndex(of: "e") else { return BigInt(field) }
        let mantissa = String(field[..<eIndex])
        let exponent = String(field[field.index(after: eIndex)...])
        guard let m = BigInt(mantissa), let e = Int(exponent), e >= 0 else { return nil }
        return m * BigInt(10).power(e)
    }
}
