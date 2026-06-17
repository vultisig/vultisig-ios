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

    func testCustomSlippageClampsToMax() {
        // Below the cap passes through untouched.
        XCTAssertEqual(SwapSlippage.clampCustomBps(50), 50)
        XCTAssertEqual(SwapSlippage.clampCustomBps(SwapSlippage.maxCustomBps), SwapSlippage.maxCustomBps)
        // Above the cap clamps to the max (matches the 1inch/LiFi 5000-bps ceiling).
        XCTAssertEqual(SwapSlippage.clampCustomBps(SwapSlippage.maxCustomBps + 1), SwapSlippage.maxCustomBps)
        XCTAssertEqual(SwapSlippage.clampCustomBps(10_000), SwapSlippage.maxCustomBps)
        XCTAssertEqual(SwapSlippage.clampCustomBps(1_000_000), SwapSlippage.maxCustomBps)
        // Negatives clamp up to zero.
        XCTAssertEqual(SwapSlippage.clampCustomBps(-100), 0)
    }

    func testMaxCustomBpsMatchesDownstreamAggregatorCeiling() {
        // The input cap must equal the downstream aggregator clamp (1inch/LiFi cap
        // at 5000 bps = 50%) so the value displayed and the value sent never diverge.
        XCTAssertEqual(SwapSlippage.maxCustomBps, 5000)
    }

    // MARK: - External-recipient route filtering (silent fund-misdirection guard)
    //
    // Only THORChain/Maya honour an external recipient (memo destination); the
    // aggregators (1inch / KyberSwap / LI.FI / SwapKit) build with the user's own
    // address. So when a recipient is set, those providers must be dropped from
    // the candidate pool before ranking — otherwise the winner could send to self
    // while the verify row shows the external address.

    private let allProviders: [SwapProvider] = [
        .thorchain, .thorchainChainnet, .thorchainStagenet, .mayachain,
        .oneinch(.ethereum), .kyberswap(.ethereum), .lifi, .swapkit
    ]

    func testRecipientFilterKeepsEveryProviderWhenNoRecipient() {
        XCTAssertEqual(
            SwapService.providersHonoringRecipient(allProviders, recipientAddress: nil),
            allProviders,
            "No external recipient must leave the candidate pool byte-identical"
        )
    }

    func testRecipientFilterTreatsBlankRecipientAsNone() {
        XCTAssertEqual(
            SwapService.providersHonoringRecipient(allProviders, recipientAddress: "   \n\t"),
            allProviders,
            "A blank/whitespace recipient is not a real recipient and must not filter providers"
        )
    }

    func testRecipientFilterDropsAggregatorsWhenRecipientSet() {
        let filtered = SwapService.providersHonoringRecipient(allProviders, recipientAddress: "0xExternalRecipient")
        XCTAssertEqual(filtered, [.thorchain, .thorchainChainnet, .thorchainStagenet, .mayachain],
                       "Only recipient-honouring routes survive when an external recipient is set")
        XCTAssertFalse(filtered.contains(.oneinch(.ethereum)))
        XCTAssertFalse(filtered.contains(.kyberswap(.ethereum)))
        XCTAssertFalse(filtered.contains(.lifi))
        XCTAssertFalse(filtered.contains(.swapkit))
    }

    func testRecipientFilterYieldsEmptyWhenOnlyAggregatorsAvailable() {
        // An EVM-only same-chain route (aggregators only): with a recipient set,
        // nothing qualifies → empty, which `fetchQuotes` maps to a clear error
        // rather than silently routing to self.
        let aggregatorsOnly: [SwapProvider] = [.oneinch(.ethereum), .kyberswap(.ethereum), .lifi, .swapkit]
        XCTAssertTrue(
            SwapService.providersHonoringRecipient(aggregatorsOnly, recipientAddress: "0xExternalRecipient").isEmpty,
            "No recipient-honouring route must yield an empty set so the caller can surface an error"
        )
    }

    func testProviderRecipientHonoringClassification() {
        XCTAssertTrue(SwapProvider.thorchain.honorsExternalRecipient)
        XCTAssertTrue(SwapProvider.thorchainChainnet.honorsExternalRecipient)
        XCTAssertTrue(SwapProvider.thorchainStagenet.honorsExternalRecipient)
        XCTAssertTrue(SwapProvider.mayachain.honorsExternalRecipient)
        XCTAssertFalse(SwapProvider.oneinch(.ethereum).honorsExternalRecipient)
        XCTAssertFalse(SwapProvider.kyberswap(.ethereum).honorsExternalRecipient)
        XCTAssertFalse(SwapProvider.lifi.honorsExternalRecipient)
        XCTAssertFalse(SwapProvider.swapkit.honorsExternalRecipient)
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
