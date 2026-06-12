//
//  DogeFeeTierTests.swift
//  VultisigAppTests
//
//  Pins the Dogecoin byte-fee math. Before this, DOGE used a flat `sats / 10`
//  divisor that ignored the user's fee tier (Low/Normal/Fast all identical) and
//  underpriced vs Android by ~2.5x. Blockchair reports DOGE at the relay-floor
//  scale (~500k sats/byte); Android rescales by 0.25 (`gas * 5 / 20`) and lands
//  on a 125k sats/byte next-block rate. `dogeByteFee` reproduces that 0.25 base
//  and applies the fee mode tier on top so the tiers actually differ.
//

@testable import VultisigApp
import XCTest
import BigInt

final class DogeFeeTierTests: XCTestCase {

    /// Live DOGE `suggested_transaction_fee_per_byte_sat` sits at the chain's
    /// relay-floor scale.
    private let liveSuggestedRate = BigInt(500_000)

    /// At the live rate, `.normal` reproduces Android's 0.25x intent exactly
    /// (500k * 0.25 * 1 = 125,000 sats/byte == Android `gas * 5 / 20`).
    func testNormalTierMatchesAndroidIntent() {
        let fee = BlockChainService.dogeByteFee(
            suggestedSatsPerByte: liveSuggestedRate,
            feeMode: .normal
        )
        XCTAssertEqual(fee, BigInt(125_000))
    }

    /// Low / Normal / Fast must produce distinct fees — the bug being fixed was
    /// that the flat `/10` made the tier selector a no-op.
    func testTiersProduceDistinctFees() {
        let low = BlockChainService.dogeByteFee(suggestedSatsPerByte: liveSuggestedRate, feeMode: .safeLow)
        let normal = BlockChainService.dogeByteFee(suggestedSatsPerByte: liveSuggestedRate, feeMode: .normal)
        let fast = BlockChainService.dogeByteFee(suggestedSatsPerByte: liveSuggestedRate, feeMode: .fast)

        XCTAssertEqual(low, BigInt(93_750))    // 500k * 0.25 * 0.75
        XCTAssertEqual(normal, BigInt(125_000)) // 500k * 0.25 * 1.0
        XCTAssertEqual(fast, BigInt(312_500))   // 500k * 0.25 * 2.5

        XCTAssertLessThan(low, normal)
        XCTAssertLessThan(normal, fast)
    }

    /// The fix raises the default (`.fast`) fee above the old flat `/10` path
    /// (50,000 sats/byte) so DOGE is no longer ~2.5x cheaper than Android.
    func testFixIsPricierThanOldFlatDivisor() {
        let oldFlat = liveSuggestedRate / 10 // 50,000
        let fast = BlockChainService.dogeByteFee(suggestedSatsPerByte: liveSuggestedRate, feeMode: .fast)
        XCTAssertGreaterThan(fast, oldFlat)
    }

    /// Even the highest tier stays below the raw suggested rate, keeping the
    /// absolute byte fee economically reasonable.
    func testFastTierStaysBelowRawSuggestedRate() {
        let fast = BlockChainService.dogeByteFee(suggestedSatsPerByte: liveSuggestedRate, feeMode: .fast)
        XCTAssertLessThan(fast, liveSuggestedRate)
    }
}
