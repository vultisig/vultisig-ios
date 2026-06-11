//
//  TerraClassicTaxTests.swift
//  VultisigAppTests
//
//  Pins the Terra Classic (columbus-5) burn-tax math that the send fee depends
//  on. Terra Classic charges a proportional burn tax (`x/tax` module,
//  `burn_tax_rate`, currently 0.5%) on every MsgSend, paid in the send denom on
//  top of gas. Before the fix, USTC sends signed a flat 1-USTC placeholder tax
//  and LUNC signed no tax at all, so any send where 0.5% exceeded the flat value
//  was rejected at broadcast after the keysign ceremony. These tests assert the
//  proportional math (rounded UP so the signed fee never undershoots the chain's
//  check) and the fail-closed rate parsing.
//

@testable import VultisigApp
import BigInt
import XCTest

final class TerraClassicTaxTests: XCTestCase {

    private let rate = TerraClassicTax.fallbackBurnTaxRate // 0.5%

    func testBurnTaxIsHalfPercentOfAmount() {
        // 1,000,000 uusd (1 USTC) -> 5,000 uusd tax.
        XCTAssertEqual(TerraClassicTax.burnTax(amount: BigInt(1_000_000), rate: rate), BigInt(5_000))
    }

    func testBurnTaxScalesWithLargeSend() throws {
        // A real on-chain LUNC send: 7,836,779,425,000 uluna -> 0.5% = 39,183,897,125.
        let amount = try XCTUnwrap(BigInt("7836779425000"))
        let expected = try XCTUnwrap(BigInt("39183897125"))
        XCTAssertEqual(TerraClassicTax.burnTax(amount: amount, rate: rate), expected)
    }

    func testBurnTaxRoundsUpNeverUndershoots() {
        // 333 * 0.005 = 1.665 -> must round UP to 2, not down to 1, so the
        // signed fee always covers (or exceeds) the chain's required tax.
        XCTAssertEqual(TerraClassicTax.burnTax(amount: BigInt(333), rate: rate), BigInt(2))
    }

    func testBurnTaxZeroAmountIsZero() {
        XCTAssertEqual(TerraClassicTax.burnTax(amount: BigInt(0), rate: rate), BigInt(0))
    }

    func testBurnTaxZeroRateIsZero() {
        XCTAssertEqual(TerraClassicTax.burnTax(amount: BigInt(1_000_000), rate: 0), BigInt(0))
    }

    func testParseRateValidDecimalString() {
        XCTAssertEqual(TerraClassicTax.parseRate("0.005000000000000000"), Decimal(string: "0.005"))
    }

    func testParseRateFallsBackOnGarbage() {
        // A malformed rate must fail CLOSED to the conservative fallback, never
        // to 0% (which would sign a tax-free tx the chain then rejects).
        XCTAssertEqual(TerraClassicTax.parseRate("not-a-number"), TerraClassicTax.fallbackBurnTaxRate)
    }

    func testParseRateFallsBackOnNegative() {
        XCTAssertEqual(TerraClassicTax.parseRate("-0.01"), TerraClassicTax.fallbackBurnTaxRate)
    }

    func testParseRateAcceptsZero() {
        // A genuine on-chain 0 rate (tax temporarily disabled by governance) is
        // valid and must be honored, not overridden by the fallback.
        XCTAssertEqual(TerraClassicTax.parseRate("0.000000000000000000"), Decimal(0))
    }

    // MARK: - isBankDenom (gates which tokens pay the tax in their own denom)

    func testIsBankDenomTrueForUUSD() {
        // USTC trades as the `uusd` bank denom — it pays gas + burn tax in uusd.
        XCTAssertTrue(TerraClassicTax.isBankDenom(contractAddress: "uusd", isNativeToken: false))
    }

    func testIsBankDenomFalseForNativeToken() {
        // The native coin (LUNC) is handled by its own native-balance branch.
        XCTAssertFalse(TerraClassicTax.isBankDenom(contractAddress: "", isNativeToken: true))
    }

    func testIsBankDenomFalseForCW20Contract() {
        // CW20 contract tokens (terra1…) pay the fee in native LUNC, not uusd.
        let cw20 = "terra1nsuqsk6kh58ulczatwev87ttq2z6r3pusulg9r24mfj2fvtzd4uq3exn26"
        XCTAssertFalse(TerraClassicTax.isBankDenom(contractAddress: cw20, isNativeToken: false))
    }

    func testIsBankDenomFalseForIBCToken() {
        let ibc = "ibc/0471F1C4E7AFD3F07702BEF6DC365268D64570F7C1FDC98EA6098DD6DE59817B"
        XCTAssertFalse(TerraClassicTax.isBankDenom(contractAddress: ibc, isNativeToken: false))
    }

    func testIsBankDenomFalseForFactoryToken() {
        XCTAssertFalse(TerraClassicTax.isBankDenom(contractAddress: "factory/terra1abc/utoken", isNativeToken: false))
    }
}
