//
//  DefaultSwapInteractorTests.swift
//  VultisigAppTests
//

import BigInt
import XCTest
@testable import VultisigApp

@MainActor
final class DefaultSwapInteractorTests: XCTestCase {

    // MARK: - fetchQuote guards
    // Note: FastVault eligibility moved off the interactor — now lives on
    // `Vault.fastVaultEligibility` populated by `FastVaultEligibilityRefresher`.
    // See `FastVaultEligibilityRefresherTests` for the eligibility logic tests.

    func testFetchQuoteReturnsNilForZeroAmount() async throws {
        let quoteService = MockQuoteService(stubbedResult: .failure(StubError.shouldNotBeCalled))
        let interactor = makeInteractor(quote: quoteService)

        let result = try await interactor.fetchQuote(
            amount: 0,
            fromCoin: .example,
            toCoin: .example,
            vault: makeVault(),
            referredCode: "",
            slippageBps: nil,
            recipientAddress: nil
        )

        XCTAssertNil(result)
        XCTAssertEqual(quoteService.fetchQuoteCallCount, 0, "Quote service must not be hit when amount is zero")
    }

    func testFetchQuoteThrowsSameAssetWhenFromEqualsTo() async {
        let quoteService = MockQuoteService(stubbedResult: .failure(StubError.shouldNotBeCalled))
        let interactor = makeInteractor(quote: quoteService)
        let btc = makeCoin(.bitcoin, ticker: "BTC")

        do {
            _ = try await interactor.fetchQuote(
                amount: 1,
                fromCoin: btc,
                toCoin: btc,
                vault: makeVault(),
                referredCode: "",
            slippageBps: nil,
            recipientAddress: nil
            )
            XCTFail("Expected throw")
        } catch {
            XCTAssertEqual(error as? SwapCryptoLogic.Errors, .sameAsset)
        }
        XCTAssertEqual(quoteService.fetchQuoteCallCount, 0)
    }

    // MARK: - fetchChainSpecific

    func testFetchChainSpecificDelegatesToBlockchainService() async throws {
        let blockchain = MockBlockChainService(
            stubbedResult: .success(.Cosmos(accountNumber: 7, sequence: 1, gas: 200_000, transactionType: 0, ibcDenomTrace: nil, gasLimit: nil))
        )
        let interactor = makeInteractor(blockchain: blockchain)

        let result = try await interactor.fetchChainSpecific(
            fromCoin: .example,
            toCoin: .example,
            fromAmount: 0.1,
            quote: nil
        )

        XCTAssertEqual(blockchain.fetchSwapCallCount, 1)
        XCTAssertEqual(blockchain.lastFromAmount, 0.1)
        if case let .Cosmos(account, _, _, _, _, _) = result {
            XCTAssertEqual(account, 7)
        } else {
            XCTFail("Unexpected variant")
        }
    }

    func testFetchChainSpecificPropagatesError() async {
        let blockchain = MockBlockChainService(stubbedResult: .failure(StubError.networkError))
        let interactor = makeInteractor(blockchain: blockchain)

        do {
            _ = try await interactor.fetchChainSpecific(
                fromCoin: .example,
                toCoin: .example,
                fromAmount: 0,
                quote: nil
            )
            XCTFail("Expected throw")
        } catch {
            XCTAssertEqual(error as? StubError, .networkError)
        }
    }

    // MARK: - updateBalance

    func testUpdateBalanceDelegatesToBalanceService() async {
        let balance = MockBalanceService()
        let interactor = makeInteractor(balance: balance)
        let coin = makeCoin(.ethereum, ticker: "ETH")

        await interactor.updateBalance(for: coin)

        XCTAssertEqual(balance.updateBalanceCallCount, 1)
        XCTAssertEqual(balance.lastUpdatedCoin, coin)
    }

    // MARK: - Discount-tier session cache

    func testFetchQuoteResolvesTierOncePerSessionAcrossManyFetches() async throws {
        let tierResolver = MockDiscountTierResolver(tier: .gold)
        let quoteService = MockQuoteService(stubbedResult: .success(.thorchain(makeThorQuote())))
        let interactor = makeInteractor(quote: quoteService, tierResolver: tierResolver)
        let vault = makeVault()
        let from = makeCoin(.ethereum, ticker: "ETH")
        let to = makeCoin(.bitcoin, ticker: "BTC")

        // Warm once on "screen load", then run several quote fetches as the user
        // types — the underlying tier resolution (incl. Thorguard eth_call) must
        // only run once for the whole session.
        await interactor.warmDiscountTier(for: vault)
        for _ in 0..<5 {
            _ = try await interactor.fetchQuote(
                amount: 1, fromCoin: from, toCoin: to, vault: vault, referredCode: "", slippageBps: nil, recipientAddress: nil
            )
        }

        XCTAssertEqual(
            tierResolver.resolveCallCount, 6,
            "resolveTierForSession is called per quote + warm-up, but caching must keep the network resolve to one"
        )
        XCTAssertEqual(
            tierResolver.networkResolveCount, 1,
            "The cached resolve (incl. Thorguard eth_call) must run exactly once across the session"
        )
    }

    func testFetchQuotePassesCachedTierDiscountToQuoteService() async throws {
        let tierResolver = MockDiscountTierResolver(tier: .gold)
        let quoteService = MockQuoteService(stubbedResult: .success(.thorchain(makeThorQuote())))
        let interactor = makeInteractor(quote: quoteService, tierResolver: tierResolver)

        let result = try await interactor.fetchQuote(
            amount: 1,
            fromCoin: makeCoin(.ethereum, ticker: "ETH"),
            toCoin: makeCoin(.bitcoin, ticker: "BTC"),
            vault: makeVault(),
            referredCode: "",
            slippageBps: nil,
            recipientAddress: nil
        )

        XCTAssertEqual(result?.vultDiscountBps, VultDiscountTier.gold.bpsDiscount)
        XCTAssertEqual(quoteService.lastVultTierDiscount, VultDiscountTier.gold.bpsDiscount)
    }

    /// The first resolution saw a VULT balance of zero — a failed or
    /// not-yet-landed fetch — and produced no tier. The tier must be re-resolved
    /// for the next quote, not pinned: a pinned nil silently overcharged the user
    /// on every later swap of the session.
    func testFetchQuoteHonoursATierThatOnlyResolvesOnTheSecondCall() async throws {
        let tierResolver = SequencedDiscountTierResolver(tiers: [nil, .gold])
        let quoteService = MockQuoteService(stubbedResult: .success(.thorchain(makeThorQuote())))
        let interactor = makeInteractor(quote: quoteService, tierResolver: tierResolver)
        let vault = makeVault()
        let from = makeCoin(.ethereum, ticker: "ETH")
        let to = makeCoin(.bitcoin, ticker: "BTC")

        let first = try await interactor.fetchQuote(
            amount: 1, fromCoin: from, toCoin: to, vault: vault, referredCode: "", slippageBps: nil, recipientAddress: nil
        )
        XCTAssertEqual(first?.vultDiscountBps, 0, "Precondition: the first quote resolved no tier")

        let second = try await interactor.fetchQuote(
            amount: 1, fromCoin: from, toCoin: to, vault: vault, referredCode: "", slippageBps: nil, recipientAddress: nil
        )

        XCTAssertEqual(tierResolver.resolveCallCount, 2, "Every quote must re-resolve the tier")
        XCTAssertEqual(
            second?.vultDiscountBps, VultDiscountTier.gold.bpsDiscount,
            "A tier that resolves late must be honoured by the next quote"
        )
        XCTAssertEqual(quoteService.lastVultTierDiscount, VultDiscountTier.gold.bpsDiscount)
    }

    /// Ties the fix to the observable symptom: a Gold vault must send
    /// `affiliate_bps = 30`, not the undiscounted 50. Mayanode's
    /// `recommended_min_amount_in` is inversely proportional to the affiliate
    /// bps, so sending 50 lowered the minimum the reporter's route was measured
    /// against and changed which routes were offered.
    func testGoldTierYieldsThirtyAffiliateBps() async throws {
        let tierResolver = MockDiscountTierResolver(tier: .gold)
        let quoteService = MockQuoteService(stubbedResult: .success(.thorchain(makeThorQuote())))
        let interactor = makeInteractor(quote: quoteService, tierResolver: tierResolver)

        let result = try await interactor.fetchQuote(
            amount: 1,
            fromCoin: makeCoin(.ethereum, ticker: "ETH"),
            toCoin: makeCoin(.bitcoin, ticker: "BTC"),
            vault: makeVault(),
            referredCode: "",
            slippageBps: nil,
            recipientAddress: nil
        )

        // The release affiliate rate is 50 bps; DEBUG builds force
        // `affiliateFeeRateBp` to 0, so the shipping base is spelled out here.
        let releaseAffiliateBps = 50
        let discount = try XCTUnwrap(result?.vultDiscountBps)
        XCTAssertEqual(
            THORChainSwaps.discountedAffiliateBps(baseBps: releaseAffiliateBps, discountBps: discount), 30,
            "A Gold vault must send affiliate_bps=30"
        )
    }

    // MARK: - Slippage + recipient threading

    func testFetchQuoteThreadsCustomSlippageToQuoteService() async throws {
        let quoteService = MockQuoteService(stubbedResult: .success(.thorchain(makeThorQuote())))
        let interactor = makeInteractor(quote: quoteService)

        _ = try await interactor.fetchQuote(
            amount: 1,
            fromCoin: makeCoin(.ethereum, ticker: "ETH"),
            toCoin: makeCoin(.bitcoin, ticker: "BTC"),
            vault: makeVault(),
            referredCode: "",
            slippageBps: 300,
            recipientAddress: nil
        )

        XCTAssertEqual(quoteService.lastSlippageBps, 300, "Custom slippage must reach the quote service")
    }

    func testFetchQuotePassesNilSlippageForAuto() async throws {
        let quoteService = MockQuoteService(stubbedResult: .success(.thorchain(makeThorQuote())))
        let interactor = makeInteractor(quote: quoteService)

        _ = try await interactor.fetchQuote(
            amount: 1,
            fromCoin: makeCoin(.ethereum, ticker: "ETH"),
            toCoin: makeCoin(.bitcoin, ticker: "BTC"),
            vault: makeVault(),
            referredCode: "",
            slippageBps: nil,
            recipientAddress: nil
        )

        XCTAssertNil(quoteService.lastSlippageBps, "Auto must pass nil so the provider default is preserved")
    }

    func testFetchQuoteThreadsExternalRecipientToQuoteService() async throws {
        let quoteService = MockQuoteService(stubbedResult: .success(.thorchain(makeThorQuote())))
        let interactor = makeInteractor(quote: quoteService)

        _ = try await interactor.fetchQuote(
            amount: 1,
            fromCoin: makeCoin(.ethereum, ticker: "ETH"),
            toCoin: makeCoin(.bitcoin, ticker: "BTC"),
            vault: makeVault(),
            referredCode: "",
            slippageBps: nil,
            recipientAddress: "external-recipient-address"
        )

        XCTAssertEqual(quoteService.lastRecipientAddress, "external-recipient-address",
                       "External recipient must reach the quote service to become the swap destination")
    }

    // MARK: - Fixtures

    private func makeInteractor(
        quote: QuoteServiceProtocol = MockQuoteService(stubbedResult: .failure(StubError.shouldNotBeCalled)),
        blockchain: BlockChainServiceProtocol = MockBlockChainService(stubbedResult: .failure(StubError.shouldNotBeCalled)),
        balance: BalanceServiceProtocol = MockBalanceService(),
        fastVault: FastVaultServiceProtocol = MockFastVaultService(),
        tierResolver: SwapDiscountTierResolving = MockDiscountTierResolver(tier: nil)
    ) -> DefaultSwapInteractor {
        DefaultSwapInteractor(
            quote: quote,
            blockchain: blockchain,
            balance: balance,
            fastVault: fastVault,
            tierResolver: tierResolver
        )
    }

    private func makeVault(localPartyID: String = "iPhone-12345") -> Vault {
        Vault(
            name: "Test Vault",
            signers: [],
            pubKeyECDSA: "test-pub-ecdsa",
            pubKeyEdDSA: "test-pub-eddsa",
            keyshares: [],
            localPartyID: localPartyID,
            hexChainCode: "hex",
            resharePrefix: nil,
            libType: .DKLS
        )
    }

    private func makeCoin(_ chain: Chain, ticker: String) -> Coin {
        let asset = CoinMeta.make(chain: chain, ticker: ticker, decimals: 8)
        return Coin(asset: asset, address: "test-address-\(ticker)", hexPublicKey: "")
    }

    private func makeThorQuote() -> ThorchainSwapQuote {
        ThorchainSwapQuote(
            dustThreshold: nil,
            expectedAmountOut: "100000000",
            expiry: 0,
            fees: Fees(affiliate: "0", asset: "RUNE", outbound: "0", total: "0", liquidity: nil, slippageBps: nil, totalBps: nil),
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

private enum StubError: Error, Equatable {
    case shouldNotBeCalled
    case networkError
}

// swiftlint:disable async_without_await unused_parameter

/// Instrumented tier resolver mirroring `VultTierService`'s session-cache
/// behaviour: the expensive half (the Thorguard eth_call) runs once and is
/// cached, while `resolveTierForSession` may be *called* many times.
private final class MockDiscountTierResolver: SwapDiscountTierResolving, @unchecked Sendable {
    private let tier: VultDiscountTier?
    private(set) var resolveCallCount = 0
    private(set) var networkResolveCount = 0
    private var cached: VultDiscountTier??

    init(tier: VultDiscountTier?) {
        self.tier = tier
    }

    @MainActor
    func resolveTierForSession(for vault: Vault) async -> VultDiscountTier? {
        resolveCallCount += 1
        if let cached {
            return cached
        }
        // Stand-in for the session-cached Thorguard eth_call.
        networkResolveCount += 1
        cached = tier
        return tier
    }
}

/// Tier resolver that answers a different tier each call, standing in for a
/// vault whose VULT balance lands after the first quote has already gone out.
private final class SequencedDiscountTierResolver: SwapDiscountTierResolving, @unchecked Sendable {
    private var tiers: [VultDiscountTier?]
    private(set) var resolveCallCount = 0

    init(tiers: [VultDiscountTier?]) {
        self.tiers = tiers
    }

    @MainActor
    func resolveTierForSession(for vault: Vault) async -> VultDiscountTier? {
        resolveCallCount += 1
        guard !tiers.isEmpty else { return nil }
        return tiers.removeFirst()
    }
}

// swiftlint:enable async_without_await unused_parameter
