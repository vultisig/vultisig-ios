//
//  LimitSwapByteCapTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

final class LimitSwapByteCapTests: XCTestCase {

    // MARK: - UTXO source: 80-byte cap

    func testUtxoSourceAcceptsShortMemo() throws {
        try assertMemoByteLength("=<:ETH.ETH:0xabc:1/14400/0:vi:50", sourceChainKind: .UTXO)
    }

    func testUtxoSourceAcceptsMemoExactlyAtLimit() throws {
        let memo = String(repeating: "x", count: 80)
        try assertMemoByteLength(memo, sourceChainKind: .UTXO)
    }

    func testUtxoSourceRejectsMemoOneByteOverLimit() {
        let memo = String(repeating: "x", count: 81)
        XCTAssertThrowsError(try assertMemoByteLength(memo, sourceChainKind: .UTXO)) { error in
            guard case let LimitSwapMemoError.memoExceedsByteLimit(actual, limit) = error else {
                return XCTFail("Expected memoExceedsByteLimit, got \(error)")
            }
            XCTAssertEqual(actual, 81)
            XCTAssertEqual(limit, 80)
        }
    }

    func testUtxoSourceRejectsRealisticReferredMemo() {
        // Same memo emitted by LimitSwapMemoBuilder for the 24h-referred BTC→ETH
        // case, with the sci-notation LIM (16e8). Even 6 bytes shorter than the
        // plain 1600000000 form (81 vs 87), it still exceeds the 80B cap.
        let memo = "=<:ETH.ETH:0x1234567890abcdef1234567890abcdef12345678:16e8/14400/0:myref/vi:10/35"
        XCTAssertEqual(memo.utf8.count, 81)
        XCTAssertThrowsError(try assertMemoByteLength(memo, sourceChainKind: .UTXO))
    }

    func testUtxoSourceRejectsTokenTargetWithReferredAffiliate() {
        // Token target (ETH.USDC-EC7) on a referred user pushes the memo past 80B
        // even with the sci-notation LIM and a non-Vultisig destination chain.
        // This is the canonical "fitness check" case from vultisig-sdk#312.
        let memo = "=<:ETH.USDC-EC7:0x1234567890abcdef1234567890abcdef12345678:16e8/14400/0:myref/vi:10/35"
        XCTAssertGreaterThan(memo.utf8.count, 80)
        XCTAssertThrowsError(try assertMemoByteLength(memo, sourceChainKind: .UTXO))
    }

    // MARK: - Non-UTXO sources: 250-byte cap

    func testEvmSourceAccepts250ByteMemo() throws {
        let memo = String(repeating: "x", count: 250)
        try assertMemoByteLength(memo, sourceChainKind: .EVM)
    }

    func testEvmSourceRejectsMemoOneByteOverLimit() {
        let memo = String(repeating: "x", count: 251)
        XCTAssertThrowsError(try assertMemoByteLength(memo, sourceChainKind: .EVM)) { error in
            guard case let LimitSwapMemoError.memoExceedsByteLimit(actual, limit) = error else {
                return XCTFail("Expected memoExceedsByteLimit, got \(error)")
            }
            XCTAssertEqual(actual, 251)
            XCTAssertEqual(limit, 250)
        }
    }

    func testCosmosSourceAcceptsLongMemoUnderNonUtxoCap() throws {
        // 200 bytes — under 250.
        let memo = String(repeating: "x", count: 200)
        try assertMemoByteLength(memo, sourceChainKind: .Cosmos)
    }

    func testCardanoSourceUsesNonUtxoCapDespiteUtxoLikeShape() throws {
        // Cardano is a separate ChainType (Ed25519, not secp256k1 OP_RETURN). The 80B cap does
        // not apply. Verify we use the 250B cap. This guards against a future change that
        // accidentally widens .UTXO to include Cardano.
        let memo = String(repeating: "x", count: 100)
        try assertMemoByteLength(memo, sourceChainKind: .Cardano)
    }

    // MARK: - UTF-8 byte count, not character count

    func testCountsUtf8BytesNotUnicodeCharacters() {
        // A single emoji is 4 UTF-8 bytes. 21 emoji = 84 bytes (over 80B even though
        // String.count would report 21 characters).
        let memo = String(repeating: "🚀", count: 21)
        XCTAssertEqual(memo.count, 21)
        XCTAssertEqual(memo.utf8.count, 84)
        XCTAssertThrowsError(try assertMemoByteLength(memo, sourceChainKind: .UTXO))
    }
}
