//
//  RippleFeeTests.swift
//  VultisigAppTests
//
//  Pins the dynamic XRP fee math behind the 180,000-drop overpayment fix
//  (issue #4535). The pre-fix code hardcoded a 180,000-drop (0.18 XRP) fee on
//  every send — ~15,000× the XRPL reference fee of 10 drops. `recommendedFee`
//  now derives the fee from the server's reported load
//  (`base_fee * load_factor / load_base`), applies a safety multiplier for the
//  TSS signing window, and clamps to `[referenceFeeDrops, maxFeeDrops]`.
//
//  - https://xrpl.org/docs/concepts/transactions/transaction-cost
//

@testable import VultisigApp
import XCTest
import BigInt

final class RippleFeeTests: XCTestCase {

    func testNoLoadUsesReferenceFeeWithSafetyMultiplier() {
        // Under no load load_factor == load_base, so open-ledger == base_fee.
        let fee = RippleFee.recommendedFee(baseFee: 10, loadFactor: 256, loadBase: 256)
        XCTAssertEqual(fee, BigInt(20)) // 10 * (256/256) * 2
    }

    func testModerateLoadScalesFee() {
        // 4× load: 10 * (1024/256) * 2 = 80 drops.
        let fee = RippleFee.recommendedFee(baseFee: 10, loadFactor: 1024, loadBase: 256)
        XCTAssertEqual(fee, BigInt(80))
    }

    func testExtremeLoadIsClampedToCeiling() {
        let fee = RippleFee.recommendedFee(baseFee: 10, loadFactor: 1_000_000, loadBase: 256)
        XCTAssertEqual(fee, BigInt(RippleFee.maxFeeDrops))
    }

    func testNeverFallsBelowReferenceFee() {
        let fee = RippleFee.recommendedFee(baseFee: 0, loadFactor: 0, loadBase: 256)
        XCTAssertEqual(fee, BigInt(RippleFee.referenceFeeDrops))
    }

    func testMissingFieldsFallBackToReferenceFee() {
        // Nil server values default to base 10, factor 1, divisor 1 → 10 * 2.
        let fee = RippleFee.recommendedFee(baseFee: nil, loadFactor: nil, loadBase: nil)
        XCTAssertEqual(fee, BigInt(20))
    }

    func testZeroLoadBaseDoesNotCrash() {
        // load_base of 0 would divide-by-zero; it must be coerced to 1.
        let fee = RippleFee.recommendedFee(baseFee: 10, loadFactor: 256, loadBase: 0)
        XCTAssertEqual(fee, BigInt(RippleFee.maxFeeDrops)) // 10 * 256 * 2 clamped
    }

    func testFeeStaysWellBelowLegacyHardcodedValue() {
        let fee = RippleFee.recommendedFee(baseFee: 10, loadFactor: 256, loadBase: 256)
        XCTAssertLessThan(fee, BigInt(180_000))
    }
}
