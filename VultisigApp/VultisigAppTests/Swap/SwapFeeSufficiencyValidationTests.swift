//
//  SwapFeeSufficiencyValidationTests.swift
//  VultisigAppTests
//
//  The `.insufficientGas` gate must validate EVM aggregator/SwapKit routes
//  against the reconciled SIGNED bond (`EVMSwapFee`), not the provider's
//  quote-time fee seed: an EVM node rejects any transaction whose account
//  can't cover `gasLimit × maxFeePerGas + value`, so a balance between the
//  stale seed and the bond used to pass validation and then fail at
//  broadcast with "insufficient funds for gas".
//
//  Covers the verify screen's refresh path (oracle fetched BEFORE the check,
//  quote-fee fallback when the oracle fetch fails — never blocking harder
//  than the pre-bond behavior) and the details screen's mirror. Non-EVM
//  routes keep validating exactly as before.
//

import BigInt
import XCTest
@testable import VultisigApp

@MainActor
final class SwapFeeSufficiencyValidationTests: XCTestCase {

    // Route: 360k gas priced by the provider at 0.5 Gwei → 0.00018 ETH seed.
    // Oracle: 1 Gwei ceiling × 900k stored limit → 0.0009 ETH signed bond.
    private let routeGas: Int64 = 360_000
    private let quoteFeeWei = BigInt(360_000) * BigInt(500_000_000)
    private let maxFeePerGasWei = BigInt(1_000_000_000)
    private let oracleGasLimit = BigInt(900_000)
    private var bondWei: BigInt { maxFeePerGasWei * oracleGasLimit }

    // MARK: - Verify screen (refreshData)

    func testRefreshBlocksWhenBalanceBelowReconciledBond() async {
        // 0.0005 ETH covers amount + quote seed (0.00028) but not amount +
        // bond (0.001) — the old order validated pre-oracle and let it pass.
        let vm = makeVerifyVM(balanceWei: "500000000000000")

        await vm.refreshData(vault: makeVault(), referredCode: "")

        XCTAssertEqual(
            vm.error as? SwapCryptoLogic.Errors,
            .insufficientGas,
            "A balance between the quote seed and the signed bond must be blocked before signing"
        )
    }

    func testRefreshPassesWhenBalanceCoversReconciledBond() async {
        let vm = makeVerifyVM(balanceWei: "2000000000000000") // 0.002 ETH ≥ amount + bond

        await vm.refreshData(vault: makeVault(), referredCode: "")

        XCTAssertNil(vm.error)
        XCTAssertEqual(vm.transaction.gas, maxFeePerGasWei, "Oracle maxFeePerGas must be committed")
        XCTAssertEqual(vm.transaction.gasLimit, oracleGasLimit, "Oracle gasLimit must be committed")
        XCTAssertEqual(vm.transaction.displayedNetworkFeeWei, bondWei)
    }

    func testRefreshFallsBackToQuoteFeeWhenOracleFetchFails() async {
        // Balance covers the quote fee; the oracle fetch fails. Validation
        // must fall back to the quote fee (never block harder than before)
        // and the fetch error surfaces exactly as it used to.
        let vm = makeVerifyVM(balanceWei: "500000000000000", chainSpecificError: TestOracleError())

        await vm.refreshData(vault: makeVault(), referredCode: "")

        XCTAssertTrue(vm.error is TestOracleError, "The oracle fetch error must surface, not a gas error")
        XCTAssertNotEqual(vm.error as? SwapCryptoLogic.Errors, .insufficientGas)
        XCTAssertEqual(vm.transaction.gas, .zero, "A failed refresh must not commit a partial update")
    }

    func testRefreshStillBlocksOnQuoteFeeWhenOracleFetchFails() async {
        // 0.0002 ETH doesn't even cover amount + quote seed (0.00028) — the
        // pre-bond gate already blocked this, and it must keep blocking.
        let vm = makeVerifyVM(balanceWei: "200000000000000", chainSpecificError: TestOracleError())

        await vm.refreshData(vault: makeVault(), referredCode: "")

        XCTAssertEqual(vm.error as? SwapCryptoLogic.Errors, .insufficientGas)
    }

    // MARK: - Details screen mirror (balanceError)

    func testDetailsBalanceErrorUsesReconciledBondForEvmAggregator() {
        let vm = makeDetailsVM(balanceWei: "500000000000000")
        vm.gas = maxFeePerGasWei
        vm.gasLimit = oracleGasLimit

        XCTAssertEqual(
            vm.balanceError,
            .insufficientGas,
            "The details gate must validate against the signed bond once the oracle loads"
        )
    }

    func testDetailsBalanceErrorPassesWhenBalanceCoversBond() {
        let vm = makeDetailsVM(balanceWei: "2000000000000000")
        vm.gas = maxFeePerGasWei
        vm.gasLimit = oracleGasLimit

        XCTAssertNil(vm.balanceError)
    }

    func testDetailsBalanceErrorKeepsQuoteFeeBeforeOracleLoads() {
        // Until chainSpecific lands (`gas == 0`) the reconciled fee falls back
        // to the quote fee — identical to the pre-bond gate.
        let vm = makeDetailsVM(balanceWei: "500000000000000")
        vm.gas = .zero
        vm.gasLimit = .zero

        XCTAssertNil(vm.balanceError, "Pre-oracle validation must keep using the quote fee")
    }

    func testDetailsBalanceErrorUnchangedForNonEvmRoute() {
        // THORChain routes validate against `thorchainFee` exactly as before —
        // the reconciliation only applies to EVM aggregator/SwapKit routes.
        let rune = makeCoin(.thorChain, ticker: "RUNE", decimals: 8, balance: "100000000") // 1 RUNE
        let vm = SwapDetailsViewModel(interactor: StubSwapInteractor())
        vm.fromCoin = rune
        vm.fromCoins = [rune]
        vm.fromAmount = "0.5"
        vm.quote = .thorchain(makeThorQuote())
        vm.thorchainFee = BigInt(2_000_000) // 0.02 RUNE
        vm.gas = BigInt(2_000_000)

        XCTAssertNil(vm.balanceError)

        vm.thorchainFee = BigInt(60_000_000) // 0.6 RUNE → 0.5 + 0.6 > 1
        XCTAssertEqual(vm.balanceError, .insufficientGas)
    }

    // MARK: - Fixtures

    private func makeQuote() -> SwapQuote {
        .oneinch(
            EVMQuote(
                dstAmount: "1000000",
                tx: EVMQuote.Transaction(
                    from: "0xfrom",
                    to: "0xrouter",
                    data: "0xdeadbeef",
                    value: "100000000000000",
                    gasPrice: "500000000",
                    gas: routeGas
                )
            ),
            fee: quoteFeeWei
        )
    }

    private func makeVerifyVM(balanceWei: String, chainSpecificError: Error? = nil) -> SwapVerifyViewModel {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, balance: balanceWei)
        let btc = makeCoin(.bitcoin, ticker: "BTC", decimals: 8, balance: "0")
        let quote = makeQuote()
        let transaction = SwapTransaction(
            fromCoin: eth,
            toCoin: btc,
            fromAmount: Decimal(string: "0.0001") ?? 0,
            quote: quote,
            gas: .zero,
            gasLimit: .zero,
            thorchainFee: .zero,
            vultDiscountBps: 0,
            referralDiscountBps: 0,
            feeCoin: eth,
            limitContext: nil,
            advancedSettings: .default
        )
        let interactor = StubSwapInteractor(
            quote: quote,
            chainSpecific: .Ethereum(
                maxFeePerGasWei: maxFeePerGasWei,
                priorityFeeWei: BigInt(1),
                nonce: 0,
                gasLimit: oracleGasLimit
            ),
            chainSpecificError: chainSpecificError
        )
        return SwapVerifyViewModel(transaction: transaction, interactor: interactor)
    }

    private func makeDetailsVM(balanceWei: String) -> SwapDetailsViewModel {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, balance: balanceWei)
        let vm = SwapDetailsViewModel(interactor: StubSwapInteractor())
        vm.fromCoin = eth
        vm.fromCoins = [eth]
        vm.fromAmount = "0.0001"
        vm.quote = makeQuote()
        return vm
    }

    private func makeCoin(_ chain: Chain, ticker: String, decimals: Int, balance: String) -> Coin {
        let asset = CoinMeta.make(chain: chain, ticker: ticker, decimals: decimals, isNativeToken: true)
        let coin = Coin(asset: asset, address: "test-address-\(ticker)", hexPublicKey: "")
        coin.rawBalance = balance
        return coin
    }

    private func makeVault() -> Vault {
        Vault(
            name: "Test Vault",
            signers: [],
            pubKeyECDSA: "test-pub-ecdsa",
            pubKeyEdDSA: "test-pub-eddsa",
            keyshares: [],
            localPartyID: "iPhone-12345",
            hexChainCode: "hex",
            resharePrefix: nil,
            libType: .DKLS
        )
    }

    private func makeThorQuote() -> ThorchainSwapQuote {
        ThorchainSwapQuote(
            dustThreshold: nil,
            expectedAmountOut: "0",
            expiry: 0,
            fees: Fees(
                affiliate: "0",
                asset: "RUNE",
                outbound: "0",
                total: "0",
                liquidity: nil,
                slippageBps: nil,
                totalBps: nil
            ),
            inboundAddress: nil,
            inboundConfirmationBlocks: nil,
            inboundConfirmationSeconds: nil,
            memo: "memo",
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
}

private struct TestOracleError: Error {}

// swiftlint:disable async_without_await unused_parameter

/// Minimal `SwapInteractor`: returns the fixed quote and either the stubbed
/// chainSpecific or a stubbed oracle failure. Everything else is unreachable
/// in these tests.
private struct StubSwapInteractor: SwapInteractor {
    var quote: SwapQuote?
    var chainSpecific: BlockChainSpecific = .Cosmos(accountNumber: 0, sequence: 0, gas: 0, transactionType: 0, ibcDenomTrace: nil, gasLimit: nil)
    var chainSpecificError: Error?

    func fetchQuote(
        amount: Decimal,
        fromCoin: Coin,
        toCoin: Coin,
        vault: Vault,
        referredCode: String,
        slippageBps: Int?,
        recipientAddress: String?
    ) async throws -> SwapQuoteResult? {
        guard let quote else { return nil }
        return SwapQuoteResult(quote: quote, allQuotes: [quote], vultDiscountBps: 0, referralDiscountBps: 0)
    }

    func fetchChainSpecific(
        fromCoin: Coin,
        toCoin: Coin,
        fromAmount: Decimal,
        quote: SwapQuote?
    ) async throws -> BlockChainSpecific {
        if let chainSpecificError { throw chainSpecificError }
        return chainSpecific
    }

    func computeThorchainFee(
        chainSpecific: BlockChainSpecific,
        fromCoin: Coin,
        fromAmount: Decimal,
        vault: Vault
    ) async throws -> BigInt {
        .zero
    }

    func assertSourceChainNotHalted(transaction: SwapTransaction) async throws {}

    func buildSwapKeysignPayload(transaction: SwapTransaction, vault: Vault) async throws -> KeysignPayload {
        throw CancellationError()
    }

    func updateBalance(for coin: Coin) async {}

    func warmDiscountTier(for vault: Vault) async {}
}

// swiftlint:enable async_without_await unused_parameter
