//
//  SwapExternalRecipientProviderTests.swift
//  VultisigAppTests
//
//  Covers extending external-recipient delivery beyond THORChain/Maya:
//   1. The eligibility gate — `SwapProvider.honorsExternalRecipient` and
//      `SwapService.providersHonoringRecipient`: THOR/Maya/SwapKit are eligible
//      when a recipient is set; the pure aggregators (1inch/Kyber/LI.FI) are
//      dropped because their recipient lives in opaque router calldata we can't
//      verify on-device.
//   2. The on-device output-target verification (`SwapRecipientVerifier`):
//      THOR/Maya pass only when the signed memo carries the recipient; SwapKit
//      passes only when the echoed `destinationAddress` matches; a mismatch (or
//      an aggregator quote slipping through) fails closed.
//

import BigInt
import XCTest
@testable import VultisigApp

final class SwapExternalRecipientProviderTests: XCTestCase {

    // MARK: - Item 1: eligibility gate

    func testHonorsExternalRecipientPerProvider() {
        XCTAssertTrue(SwapProvider.thorchain.honorsExternalRecipient)
        XCTAssertTrue(SwapProvider.thorchainChainnet.honorsExternalRecipient)
        XCTAssertTrue(SwapProvider.thorchainStagenet.honorsExternalRecipient)
        XCTAssertTrue(SwapProvider.mayachain.honorsExternalRecipient)
        XCTAssertTrue(SwapProvider.swapkit.honorsExternalRecipient, "SwapKit delivers via destinationAddress + echo verification")

        XCTAssertFalse(SwapProvider.oneinch(.ethereum).honorsExternalRecipient, "1inch recipient is un-verifiable router calldata")
        XCTAssertFalse(SwapProvider.kyberswap(.ethereum).honorsExternalRecipient, "Kyber recipient is un-verifiable router calldata")
        XCTAssertFalse(SwapProvider.lifi.honorsExternalRecipient, "LI.FI recipient is un-verifiable router calldata")
    }

    func testProvidersHonoringRecipientUnchangedWithNoRecipient() {
        let all: [SwapProvider] = [.thorchain, .oneinch(.ethereum), .kyberswap(.ethereum), .lifi, .swapkit]
        XCTAssertEqual(
            SwapService.providersHonoringRecipient(all, recipientAddress: nil),
            all,
            "No recipient must leave the candidate pool byte-identical"
        )
        XCTAssertEqual(
            SwapService.providersHonoringRecipient(all, recipientAddress: "   "),
            all,
            "Blank/whitespace recipient counts as no recipient"
        )
    }

    func testProvidersHonoringRecipientDropsUnverifiableAggregators() {
        let all: [SwapProvider] = [.thorchain, .mayachain, .swapkit, .oneinch(.ethereum), .kyberswap(.ethereum), .lifi]
        let filtered = SwapService.providersHonoringRecipient(all, recipientAddress: "0xRecipient")
        XCTAssertEqual(
            filtered,
            [.thorchain, .mayachain, .swapkit],
            "With a recipient set, only THOR/Maya/SwapKit survive"
        )
    }

    // MARK: - Item 2a: THOR/Maya memo verification

    func testVerifierPassesWhenThorMemoCarriesRecipient() throws {
        let recipient = "bc1qexamplerecipientaddr"
        let quote = SwapQuote.thorchain(makeThorQuote(memo: "=:BTC.BTC:\(recipient):0/1/0:vi:50"))
        XCTAssertNoThrow(try SwapRecipientVerifier.verify(quote: quote, recipient: recipient))
    }

    func testVerifierIsCaseInsensitiveOnMemo() throws {
        let quote = SwapQuote.mayachain(makeThorQuote(memo: "=:BTC.BTC:BC1QEXAMPLE:0"))
        XCTAssertNoThrow(try SwapRecipientVerifier.verify(quote: quote, recipient: "bc1qexample"))
    }

    func testVerifierFailsWhenThorMemoMissesRecipient() {
        // The memo bakes the user's OWN address — a provider that dropped the
        // recipient. Must fail closed.
        let quote = SwapQuote.thorchain(makeThorQuote(memo: "=:BTC.BTC:bc1qOWNaddress:0"))
        XCTAssertThrowsError(try SwapRecipientVerifier.verify(quote: quote, recipient: "bc1qEXTERNALrecipient")) {
            XCTAssertEqual($0 as? SwapError, .recipientVerificationFailed)
        }
    }

    // MARK: - Item 2b: SwapKit echo verification

    func testVerifierPassesWhenSwapKitEchoesRecipient() throws {
        // Fixture's destinationAddress is 0xd8dA6BF2…96045.
        let response = try SwapKitFixtureLoader.decode(SwapKitSwapResponse.self, from: "v3-real-btc-all-swap")
        let quote = SwapQuote.swapkit(response, fee: nil, subProvider: response.subProvider)
        XCTAssertNoThrow(
            try SwapRecipientVerifier.verify(quote: quote, recipient: "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045")
        )
        // Case-insensitive (EVM checksum casing) still matches.
        XCTAssertNoThrow(
            try SwapRecipientVerifier.verify(quote: quote, recipient: "0xd8da6bf26964af9d7eed9e03e53415d37aa96045")
        )
    }

    func testVerifierFailsWhenSwapKitEchoMismatches() throws {
        let response = try SwapKitFixtureLoader.decode(SwapKitSwapResponse.self, from: "v3-real-btc-all-swap")
        let quote = SwapQuote.swapkit(response, fee: nil, subProvider: response.subProvider)
        XCTAssertThrowsError(
            try SwapRecipientVerifier.verify(quote: quote, recipient: "0xsomeotheraddress")
        ) {
            XCTAssertEqual($0 as? SwapError, .recipientVerificationFailed)
        }
    }

    // MARK: - Item 2c: aggregators are never verifiable

    func testVerifierFailsForAggregatorQuotes() {
        let evm = SwapQuote.oneinch(makeEVMQuote(), fee: nil)
        XCTAssertThrowsError(try SwapRecipientVerifier.verify(quote: evm, recipient: "0xRecipient")) {
            XCTAssertEqual($0 as? SwapError, .recipientVerificationFailed, "1inch can't expose a verifiable output target")
        }
        let lifi = SwapQuote.lifi(makeEVMQuote(), fee: nil, integratorFee: nil)
        XCTAssertThrowsError(try SwapRecipientVerifier.verify(quote: lifi, recipient: "0xRecipient")) {
            XCTAssertEqual($0 as? SwapError, .recipientVerificationFailed)
        }
    }

    // MARK: - Fixtures

    private func makeThorQuote(memo: String) -> ThorchainSwapQuote {
        ThorchainSwapQuote(
            dustThreshold: nil,
            expectedAmountOut: "100000000",
            expiry: 0,
            fees: Fees(affiliate: "0", asset: "RUNE", outbound: "0", total: "0", liquidity: nil, slippageBps: nil, totalBps: nil),
            inboundAddress: nil,
            inboundConfirmationBlocks: nil,
            inboundConfirmationSeconds: nil,
            memo: memo,
            notes: "",
            outboundDelayBlocks: 0,
            outboundDelaySeconds: 0,
            recommendedMinAmountIn: "0",
            slippageBps: nil,
            totalSwapSeconds: nil,
            warning: "",
            router: nil,
            maxStreamingQuantity: nil
        )
    }

    private func makeEVMQuote() -> EVMQuote {
        EVMQuote(
            dstAmount: "100000000",
            tx: EVMQuote.Transaction(from: "0xfrom", to: "0xrouter", data: "0xdeadbeef", value: "0", gasPrice: "0", gas: 0)
        )
    }
}
