//
//  SwapDraftAdapterTests.swift
//  VultisigAppTests
//
//  Round-trips `SwapTransaction → SwapDraft → SwapTransaction` and asserts
//  every property is preserved. The adapter is the bridge that lets new
//  draft-based code paths interoperate with the legacy `@Published` plumbing
//  during §1–§4. Both the adapter file and these tests are deleted in §5
//  alongside `SwapTransaction` itself.
//

import BigInt
import XCTest
@testable import VultisigApp

@MainActor
final class SwapDraftAdapterTests: XCTestCase {

    func testRoundTripPreservesEveryField() {
        let original = SwapTransaction()
        original.fromAmount = "1.5"
        original.thorchainFee = BigInt(12_345)
        original.gas = BigInt(1_000)
        original.vultDiscountBps = 50
        original.referralDiscountBps = 5
        original.quote = nil
        original.isFastVault = true
        original.fastVaultPassword = "secret"
        original.pendingRetryReason = .staleNonce
        original.fromCoin = .example
        original.toCoin = .example
        original.fromCoins = [.example]
        original.toCoins = [.example]

        let draft = SwapDraft(from: original)
        let restored = SwapTransaction()
        draft.apply(to: restored)

        XCTAssertEqual(restored.fromAmount, "1.5")
        XCTAssertEqual(restored.thorchainFee, BigInt(12_345))
        XCTAssertEqual(restored.gas, BigInt(1_000))
        XCTAssertEqual(restored.vultDiscountBps, 50)
        XCTAssertEqual(restored.referralDiscountBps, 5)
        XCTAssertNil(restored.quote)
        XCTAssertTrue(restored.isFastVault)
        XCTAssertEqual(restored.fastVaultPassword, "secret")
        XCTAssertEqual(restored.pendingRetryReason, .staleNonce)
        XCTAssertEqual(restored.fromCoin, .example)
        XCTAssertEqual(restored.toCoin, .example)
        XCTAssertEqual(restored.fromCoins, [.example])
        XCTAssertEqual(restored.toCoins, [.example])
    }

    func testRoundTripPreservesDefaultValues() {
        let original = SwapTransaction()
        let draft = SwapDraft(from: original)
        let restored = SwapTransaction()
        draft.apply(to: restored)

        XCTAssertEqual(restored.fromAmount, "")
        XCTAssertEqual(restored.thorchainFee, .zero)
        XCTAssertEqual(restored.gas, .zero)
        XCTAssertEqual(restored.vultDiscountBps, 0)
        XCTAssertEqual(restored.referralDiscountBps, 0)
        XCTAssertNil(restored.quote)
        XCTAssertFalse(restored.isFastVault)
        XCTAssertEqual(restored.fastVaultPassword, "")
        XCTAssertNil(restored.pendingRetryReason)
        XCTAssertEqual(restored.fromCoin, .example)
        XCTAssertEqual(restored.toCoin, .example)
        XCTAssertEqual(restored.fromCoins, [])
        XCTAssertEqual(restored.toCoins, [])
    }

    func testDraftIsEquatable() {
        let a = SwapDraft(from: SwapTransaction())
        let b = SwapDraft(from: SwapTransaction())
        XCTAssertEqual(a, b)

        var c = a
        c.fromAmount = "2.0"
        XCTAssertNotEqual(a, c)
    }
}
