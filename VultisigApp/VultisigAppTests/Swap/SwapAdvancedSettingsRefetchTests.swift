//
//  SwapAdvancedSettingsRefetchTests.swift
//  VultisigAppTests
//
//  Task B: re-fetch quotes when the Advanced Settings sheet closes IF a
//  quote-affecting setting (slippage / gas limit / external recipient) changed,
//  but NEVER for route/provider selection (which only picks among quotes already
//  fetched). The VM snapshots settings on open and compares on close.
//

import BigInt
import XCTest
@testable import VultisigApp

@MainActor
final class SwapAdvancedSettingsRefetchTests: XCTestCase {

    func testSlippageChangeTriggersRefetch() async {
        let (vm, interactor) = makeVM()
        vm.snapshotAdvancedSettings()
        vm.advancedSettings.slippage = .custom(bps: 300)

        let before = interactor.fetchQuoteCallCount
        vm.advancedSettingsSheetDidClose(vault: makeVault(), referredCode: "")
        await vm.waitForQuoteTask()

        XCTAssertEqual(interactor.fetchQuoteCallCount, before + 1, "A slippage change must re-fetch on close")
    }

    func testGasLimitChangeTriggersRefetch() async {
        let (vm, interactor) = makeVM()
        vm.snapshotAdvancedSettings()
        vm.advancedSettings.gasLimit = 300_000

        let before = interactor.fetchQuoteCallCount
        vm.advancedSettingsSheetDidClose(vault: makeVault(), referredCode: "")
        await vm.waitForQuoteTask()

        XCTAssertEqual(interactor.fetchQuoteCallCount, before + 1, "A gas-limit change must re-fetch on close")
    }

    func testExternalRecipientChangeTriggersRefetch() async {
        let (vm, interactor) = makeVM()
        vm.snapshotAdvancedSettings()
        vm.advancedSettings.externalRecipient = "0xExternalRecipient"

        let before = interactor.fetchQuoteCallCount
        vm.advancedSettingsSheetDidClose(vault: makeVault(), referredCode: "")
        await vm.waitForQuoteTask()

        XCTAssertEqual(interactor.fetchQuoteCallCount, before + 1, "An external-recipient change must re-fetch on close (it changes provider eligibility)")
    }

    func testNoChangeDoesNotRefetch() {
        let (vm, interactor) = makeVM()
        vm.snapshotAdvancedSettings()
        // Nothing changes while the sheet is open.

        let before = interactor.fetchQuoteCallCount
        vm.advancedSettingsSheetDidClose(vault: makeVault(), referredCode: "")

        // `fetchQuotes` flips `isLoadingQuotes` true synchronously before it
        // spawns its task, so a re-fetch — debounced or not — is observable
        // immediately; no timed sleep needed. The no-change guard returns before
        // touching either, so both stay put.
        XCTAssertFalse(vm.isLoadingQuotes, "No relevant change must not start a fetch")
        XCTAssertEqual(interactor.fetchQuoteCallCount, before, "No relevant change must not re-fetch")
    }

    func testRouteSelectionDoesNotTriggerRefetch() {
        let (vm, interactor) = makeVM()
        // Two quotes so a provider pick is possible.
        let best = SwapQuote.thorchain(makeThorQuote(expectedAmountOut: "300000000"))
        let alt = SwapQuote.oneinch(makeEVMQuote(dstAmount: "100000000"), fee: nil)
        vm.bestQuote = best
        vm.allQuotes = [best, alt]

        vm.snapshotAdvancedSettings()
        // Pick a route while the sheet is "open" — selectedQuote is NOT part of
        // advancedSettings, so the close must not re-fetch.
        vm.selectProvider(alt)

        let before = interactor.fetchQuoteCallCount
        vm.advancedSettingsSheetDidClose(vault: makeVault(), referredCode: "")

        // Route selection isn't part of `advancedSettings`, so the close path's
        // no-change guard returns synchronously — `isLoadingQuotes` would be true
        // here had any fetch started, so checking it is deterministic.
        XCTAssertFalse(vm.isLoadingQuotes, "Route selection must not start a fetch")
        XCTAssertEqual(interactor.fetchQuoteCallCount, before, "Route selection must NOT trigger a re-fetch")
        XCTAssertEqual(vm.selectedQuote, alt, "The route pick is preserved")
    }

    // MARK: - Fixtures

    private func makeVM() -> (SwapDetailsViewModel, RefetchMockInteractor) {
        let interactor = RefetchMockInteractor()
        let vm = SwapDetailsViewModel(interactor: interactor)
        vm.fromCoin = makeCoin(.thorChain, ticker: "RUNE", balance: "100000000000")
        vm.toCoin = makeCoin(.bitcoin, ticker: "BTC")
        vm.fromAmount = "1"
        return (vm, interactor)
    }

    private func makeVault() -> Vault {
        Vault(
            name: "Test Vault", signers: [], pubKeyECDSA: "e", pubKeyEdDSA: "d",
            keyshares: [], localPartyID: "iPhone", hexChainCode: "hex",
            resharePrefix: nil, libType: .DKLS
        )
    }

    private func makeCoin(_ chain: Chain, ticker: String, balance: String = "0") -> Coin {
        let asset = CoinMeta.make(chain: chain, ticker: ticker, decimals: 8, isNativeToken: true)
        let coin = Coin(asset: asset, address: "test-address-\(ticker)", hexPublicKey: "")
        coin.rawBalance = balance
        return coin
    }

    private func makeThorQuote(expectedAmountOut: String) -> ThorchainSwapQuote {
        ThorchainSwapQuote(
            dustThreshold: nil, expectedAmountOut: expectedAmountOut, expiry: 0,
            fees: Fees(affiliate: "0", asset: "RUNE", outbound: "0", total: "0", liquidity: nil, slippageBps: nil, totalBps: nil),
            inboundAddress: nil, inboundConfirmationBlocks: nil, inboundConfirmationSeconds: nil,
            memo: "memo", notes: "", outboundDelayBlocks: 0, outboundDelaySeconds: 0,
            recommendedMinAmountIn: "0", slippageBps: nil, totalSwapSeconds: nil, warning: "",
            router: nil, maxStreamingQuantity: nil
        )
    }

    private func makeEVMQuote(dstAmount: String) -> EVMQuote {
        EVMQuote(dstAmount: dstAmount, tx: EVMQuote.Transaction(from: "0xf", to: "0xt", data: "0x", value: "0", gasPrice: "0", gas: 0))
    }
}

private extension SwapDetailsViewModel {
    func waitForQuoteTask() async {
        for _ in 0..<200 where isLoadingQuotes {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

// swiftlint:disable async_without_await unused_parameter

@MainActor
private final class RefetchMockInteractor: SwapInteractor {
    private(set) var fetchQuoteCallCount = 0

    func fetchQuote(
        amount: Decimal, fromCoin: Coin, toCoin: Coin, vault: Vault,
        referredCode: String, slippageBps: Int?, recipientAddress: String?
    ) async throws -> SwapQuoteResult? {
        fetchQuoteCallCount += 1
        let quote = SwapQuote.thorchain(ThorchainSwapQuote(
            dustThreshold: nil, expectedAmountOut: "100000000", expiry: 0,
            fees: Fees(affiliate: "0", asset: "RUNE", outbound: "0", total: "0", liquidity: nil, slippageBps: nil, totalBps: nil),
            inboundAddress: nil, inboundConfirmationBlocks: nil, inboundConfirmationSeconds: nil,
            memo: "memo", notes: "", outboundDelayBlocks: 0, outboundDelaySeconds: 0,
            recommendedMinAmountIn: "0", slippageBps: nil, totalSwapSeconds: nil, warning: "",
            router: nil, maxStreamingQuantity: nil
        ))
        return SwapQuoteResult(quote: quote, vultDiscountBps: 0, referralDiscountBps: 0)
    }

    func fetchChainSpecific(fromCoin: Coin, toCoin: Coin, fromAmount: Decimal, quote: SwapQuote?) async throws -> BlockChainSpecific {
        .Cosmos(accountNumber: 0, sequence: 0, gas: 0, transactionType: 0, ibcDenomTrace: nil, gasLimit: nil)
    }

    func computeThorchainFee(chainSpecific: BlockChainSpecific, fromCoin: Coin, fromAmount: Decimal, vault: Vault) async throws -> BigInt {
        .zero
    }

    func buildSwapKeysignPayload(transaction: SwapTransaction, vault: Vault) async throws -> KeysignPayload {
        throw CancellationError()
    }

    func assertSourceChainNotHalted(transaction: SwapTransaction) async throws {}

    func updateBalance(for coin: Coin) async {}
    func warmDiscountTier(for vault: Vault) async {}
}

// swiftlint:enable async_without_await unused_parameter
