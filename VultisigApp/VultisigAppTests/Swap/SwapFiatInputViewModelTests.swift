import BigInt
import SwiftData
import XCTest
@testable import VultisigApp

@MainActor
final class SwapFiatInputViewModelTests: XCTestCase {
    private var containers: [ModelContainer] = []

    func testFiatEditReachesQuoteAndTransactionAsExactTokens() async throws {
        let (vm, interactor) = makeVM(rate: 3)
        let vault = try makeVault()
        vm.toggleFromInputMode()
        vm.setFromInputEditing(true)
        vm.editFromInput("10", vault: vault, immediate: true)
        await settle(vm)
        let exact = Decimal(string: "3.333333333333333333")!
        XCTAssertEqual(interactor.amounts, [exact])
        XCTAssertEqual(vm.fromAmountDecimal, exact)
        XCTAssertEqual(vm.makeTransaction()?.fromAmount, exact)
    }

    func testTogglesAndRateRefreshNeverRequestOrRevalueTokens() throws {
        var rate: Double? = 3
        let interactor = FiatInputInteractor()
        let vm = SwapDetailsViewModel(interactor: interactor, inputRate: { _, _ in rate })
        vm.fromCoin = makeCoin(.ethereum, ticker: "ETH", decimals: 18)
        let exact = "0" + (Locale.current.decimalSeparator ?? ".") + "123456789012345678"
        vm.fromAmount = exact
        vm.refreshFromInputContext()
        for _ in 0..<10 { vm.toggleFromInputMode() }
        XCTAssertEqual(vm.fromAmount, exact)
        vm.toggleFromInputMode()
        vm.setFromInputEditing(true)
        rate = 5
        vm.refreshFromInputContext()
        XCTAssertEqual(vm.amountInput.context?.rate, 3)
        vm.setFromInputEditing(false)
        XCTAssertEqual(vm.amountInput.context?.rate, 5)
        XCTAssertEqual(vm.fromAmount, exact)
        XCTAssertTrue(interactor.amounts.isEmpty)
    }

    func testPresetUsesCanonicalTokensAndOneImmediateRequest() async throws {
        let (vm, interactor) = makeVM(rate: 3)
        let vault = try makeVault()
        vm.toggleFromInputMode()
        let exact = "0" + (Locale.current.decimalSeparator ?? ".") + "123456789012345678"
        vm.fromAmount = exact
        vm.updateFromAmount(vault: vault, immediate: true)
        await settle(vm)
        XCTAssertEqual(interactor.amounts.count, 1)
        XCTAssertEqual(vm.fromAmount, exact)
        XCTAssertTrue(vm.isFromInputFiat)
        XCTAssertEqual(vm.fromInputText, "0" + (Locale.current.decimalSeparator ?? ".") + "37")
    }

    func testInvalidFiatClearsQuoteImmediately() async throws {
        let (vm, _) = makeVM(rate: 2.5)
        let vault = try makeVault()
        vm.toggleFromInputMode()
        vm.setFromInputEditing(true)
        vm.editFromInput("10", vault: vault, immediate: true)
        await settle(vm)
        XCTAssertNotNil(vm.quote)
        vm.editFromInput("10..", vault: vault)
        XCTAssertNil(vm.quote)
        XCTAssertFalse(vm.validateForm())
        XCTAssertNil(vm.makeTransaction())
        XCTAssertEqual(vm.fromInputText, "10..")
    }

    func testRapidFiatTypingUsesExistingCancellationAndDebounce() async throws {
        let (vm, interactor) = makeVM(rate: 2.5)
        let vault = try makeVault()
        vm.toggleFromInputMode()
        vm.setFromInputEditing(true)
        vm.editFromInput("1", vault: vault)
        vm.editFromInput("10", vault: vault)
        XCTAssertTrue(interactor.amounts.isEmpty)
        await settle(vm)
        XCTAssertEqual(interactor.amounts, [4])
    }

    func testSourceAndCurrencyChangesExitFiatWithoutReinterpretingAmount() {
        let (vm, _) = makeVM(rate: 2.5)
        vm.fromAmount = "4"
        vm.toggleFromInputMode()
        vm.fromCoin = makeCoin(.bitcoin, ticker: "BTC", decimals: 8)
        XCTAssertFalse(vm.isFromInputFiat)
        XCTAssertEqual(vm.fromAmount, "4")
        vm.toggleFromInputMode()
        let differentCurrency: SettingsCurrency = SettingsCurrency.current == .USD ? .EUR : .USD
        vm.refreshFromInputContext(currency: differentCurrency)
        XCTAssertFalse(vm.isFromInputFiat)
        XCTAssertEqual(vm.fromAmount, "4")
    }

    func testDestinationChangePreservesSourceInputMode() {
        let (vm, _) = makeVM(rate: 2.5)
        vm.fromAmount = "4"
        vm.toggleFromInputMode()
        vm.toCoin = makeCoin(.litecoin, ticker: "LTC", decimals: 8)
        XCTAssertTrue(vm.isFromInputFiat)
        XCTAssertEqual(vm.fromAmount, "4")
    }

    private func makeVM(rate: Double) -> (SwapDetailsViewModel, FiatInputInteractor) {
        let interactor = FiatInputInteractor()
        let vm = SwapDetailsViewModel(interactor: interactor, inputRate: { _, _ in rate })
        vm.fromCoin = makeCoin(.ethereum, ticker: "ETH", decimals: 18)
        vm.toCoin = makeCoin(.bitcoin, ticker: "BTC", decimals: 8)
        return (vm, interactor)
    }

    private func makeCoin(_ chain: Chain, ticker: String, decimals: Int) -> Coin {
        let coin = Coin(asset: CoinMeta.make(chain: chain, ticker: ticker, decimals: decimals, isNativeToken: true),
                        address: UUID().uuidString, hexPublicKey: UUID().uuidString)
        coin.rawBalance = "1000000000000000000000000000000"
        return coin
    }

    private func makeVault() throws -> Vault {
        let identity = UUID().uuidString
        let vault = Vault(name: "fiat-\(identity)", signers: [], pubKeyECDSA: "ecdsa-\(identity)",
                          pubKeyEdDSA: "eddsa-\(identity)", keyshares: [], localPartyID: "party-\(identity)",
                          hexChainCode: "chain-\(identity)", resharePrefix: nil, libType: .DKLS)
        let container = try ModelContainer(for: Vault.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        containers.append(container)
        container.mainContext.insert(vault)
        return vault
    }

    private func settle(_ vm: SwapDetailsViewModel) async {
        for _ in 0..<200 where vm.isLoadingQuotes || vm.isLoadingFees {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(vm.isLoadingQuotes)
        XCTAssertFalse(vm.isLoadingFees)
    }
}

// swiftlint:disable async_without_await unused_parameter
@MainActor
private final class FiatInputInteractor: SwapInteractor {
    private(set) var amounts: [Decimal] = []

    func fetchQuote(amount: Decimal, fromCoin: Coin, toCoin: Coin, vault: Vault,
                    referredCode: String, slippageBps: Int?, recipientAddress: String?) async throws -> SwapQuoteResult? {
        amounts.append(amount)
        let quote = ThorchainSwapQuote(
            dustThreshold: nil, expectedAmountOut: "100000000", expiry: 0,
            fees: Fees(affiliate: "0", asset: "BTC", outbound: "0", total: "0", liquidity: nil, slippageBps: nil, totalBps: nil),
            inboundAddress: nil, inboundConfirmationBlocks: nil, inboundConfirmationSeconds: nil,
            memo: "memo", notes: "", outboundDelayBlocks: 0, outboundDelaySeconds: 0,
            recommendedMinAmountIn: "0", slippageBps: nil, totalSwapSeconds: nil,
            warning: "", router: nil, maxStreamingQuantity: nil
        )
        return SwapQuoteResult(quote: .thorchain(quote), vultDiscountBps: 0, referralDiscountBps: 0)
    }

    func fetchChainSpecific(fromCoin: Coin, toCoin: Coin, fromAmount: Decimal, quote: SwapQuote?) async throws -> BlockChainSpecific {
        .Cosmos(accountNumber: 0, sequence: 0, gas: 0, transactionType: 0, ibcDenomTrace: nil, gasLimit: nil)
    }

    func computeThorchainFee(chainSpecific: BlockChainSpecific, fromCoin: Coin, fromAmount: Decimal, vault: Vault) async throws -> BigInt { 1 }
    func assertSourceChainNotHalted(transaction: SwapTransaction) async throws {}
    func buildSwapKeysignPayload(transaction: SwapTransaction, vault: Vault) async throws -> KeysignPayload { throw CancellationError() }
    func updateBalance(for coin: Coin) async {}
    func warmDiscountTier(for vault: Vault) async {}
}
// swiftlint:enable async_without_await unused_parameter
