//
//  SwapAdvancedSettingsTests.swift
//  VultisigAppTests
//

import BigInt
import XCTest
@testable import VultisigApp

final class SwapAdvancedSettingsTests: XCTestCase {

    // MARK: - SwapSlippage

    func testAutoSlippageHasNilBps() {
        XCTAssertNil(SwapSlippage.auto.bps)
    }

    func testPresetAndCustomExposeBps() {
        XCTAssertEqual(SwapSlippage.preset(bps: 50).bps, 50)
        XCTAssertEqual(SwapSlippage.custom(bps: 275).bps, 275)
    }

    func testFormatTrimsTrailingZeros() {
        XCTAssertEqual(SwapSlippage.format(bps: 50), "0.5%")
        XCTAssertEqual(SwapSlippage.format(bps: 100), "1%")
        XCTAssertEqual(SwapSlippage.format(bps: 300), "3%")
    }

    // MARK: - SwapAdvancedSettings.isActive

    func testDefaultSettingsAreInactive() {
        XCTAssertFalse(SwapAdvancedSettings.default.isActive)
    }

    func testCustomSlippageMakesSettingsActive() {
        var settings = SwapAdvancedSettings.default
        settings.slippage = .preset(bps: 100)
        XCTAssertTrue(settings.isActive)
    }

    func testGasLimitMakesSettingsActive() {
        var settings = SwapAdvancedSettings.default
        settings.gasLimit = BigUInt(300_000)
        XCTAssertTrue(settings.isActive)
    }

    func testExternalRecipientMakesSettingsActive() {
        var settings = SwapAdvancedSettings.default
        settings.externalRecipient = "0xabc"
        XCTAssertTrue(settings.isActive)
    }

    func testBlankExternalRecipientNormalizesToNil() {
        var settings = SwapAdvancedSettings.default
        settings.externalRecipient = "   "
        XCTAssertNil(settings.externalRecipient)
        XCTAssertFalse(settings.isActive)

        settings.externalRecipient = ""
        XCTAssertNil(settings.externalRecipient)

        settings.externalRecipient = "\n\t"
        XCTAssertNil(settings.externalRecipient)
    }

    func testExternalRecipientIsTrimmed() {
        var settings = SwapAdvancedSettings.default
        settings.externalRecipient = "  0xabc  "
        XCTAssertEqual(settings.externalRecipient, "0xabc")
        XCTAssertTrue(settings.isActive)
    }

    // MARK: - SwapTransaction recipient surfacing (verify screen)

    func testRecipientDefaultsToToCoinAddressWithoutExternalRecipient() {
        let transaction = makeTransaction(externalRecipient: nil)
        XCTAssertFalse(transaction.hasExternalRecipient)
        XCTAssertEqual(transaction.recipientAddress, transaction.toCoin.address)
    }

    func testRecipientUsesExternalRecipientWhenSet() {
        let transaction = makeTransaction(externalRecipient: "external-address")
        XCTAssertTrue(transaction.hasExternalRecipient)
        XCTAssertEqual(transaction.recipientAddress, "external-address")
    }

    // MARK: - Fixture

    private func makeTransaction(externalRecipient: String?) -> SwapTransaction {
        var settings = SwapAdvancedSettings.default
        settings.externalRecipient = externalRecipient
        let example = SwapTransaction.example
        return SwapTransaction(
            fromCoin: example.fromCoin,
            toCoin: example.toCoin,
            fromAmount: example.fromAmount,
            quote: example.quote,
            gas: example.gas,
            thorchainFee: example.thorchainFee,
            vultDiscountBps: example.vultDiscountBps,
            referralDiscountBps: example.referralDiscountBps,
            feeCoin: example.feeCoin,
            advancedSettings: settings
        )
    }
}
