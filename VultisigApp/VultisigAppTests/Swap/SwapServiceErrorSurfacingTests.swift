//
//  SwapServiceErrorSurfacingTests.swift
//  VultisigAppTests
//
//  Locks the error-surfacing rule used when every eligible swap provider fails
//  to return a usable quote. SwapKit is an optional aggregator layered on top
//  of the core routing providers (THORChain/Maya/1inch/KyberSwap/LI.FI); its
//  transient infra errors — most notably `addressScreeningFailed` ("Address
//  screening failed — contact support") — must never mask a core provider's
//  more meaningful error and make a routable pair (e.g. ETH→GRT via KyberSwap)
//  look permanently broken.
//

import XCTest
@testable import VultisigApp

final class SwapServiceErrorSurfacingTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "forcedSwapProvider")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "forcedSwapProvider")
        super.tearDown()
    }

    func testPrefersCoreProviderErrorOverSwapKitScreeningError() {
        // The reported case: SwapKit's screening error wins the task-completion
        // race, but a core provider also failed with a real routing error. The
        // core provider's error must surface, not SwapKit's "contact support".
        let errors: [Error] = [
            SwapKitError.addressScreeningFailed,
            SwapError.routeUnavailable
        ]
        let surfaced = SwapService.surfacedQuoteError(from: errors)
        XCTAssertTrue(surfaced is SwapError)
        XCTAssertEqual((surfaced as? SwapError), .routeUnavailable)
    }

    func testPrefersCoreProviderErrorRegardlessOfOrder() {
        // Task-completion order is non-deterministic; the SwapKit error must be
        // skipped even when it's collected first.
        let swapKitFirst: [Error] = [
            SwapKitError.addressScreeningFailed,
            SwapError.swapAmountTooSmall
        ]
        let swapKitLast: [Error] = [
            SwapError.swapAmountTooSmall,
            SwapKitError.addressScreeningFailed
        ]
        XCTAssertEqual(SwapService.surfacedQuoteError(from: swapKitFirst) as? SwapError, .swapAmountTooSmall)
        XCTAssertEqual(SwapService.surfacedQuoteError(from: swapKitLast) as? SwapError, .swapAmountTooSmall)
    }

    func testFallsBackToSwapKitErrorWhenItIsTheOnlyProvider() {
        // SwapKit-only pairs (TON/Cardano/Sui) have no core provider to fall back
        // on, so the SwapKit error is the only meaningful signal and must surface.
        let errors: [Error] = [SwapKitError.noRoutesFound]
        let surfaced = SwapService.surfacedQuoteError(from: errors)
        XCTAssertEqual(surfaced as? SwapKitError, .noRoutesFound)
    }

    func testReturnsNilWhenNoErrors() {
        XCTAssertNil(SwapService.surfacedQuoteError(from: []))
    }

    func testMultipleSwapKitErrorsSurfaceFirstWhenNoCoreError() {
        let errors: [Error] = [
            SwapKitError.addressScreeningFailed,
            SwapKitError.unableToBuildTransaction
        ]
        XCTAssertEqual(SwapService.surfacedQuoteError(from: errors) as? SwapKitError, .addressScreeningFailed)
    }

    // MARK: - A classified verdict beats an unclassified upstream relay

    func testClassifiedVerdictWinsOverRawProviderRelayRegardlessOfOrder() {
        // The reported case: a poolless THORChain↔EVM pair fails on THORChain and
        // MAYAChain at once. THORChain's body classifies to `.noLiquidityPool`;
        // an unclassifiable body only reaches `.serverError`. `errors` arrives in
        // task-completion order, so without this rule the user saw whichever node
        // happened to answer first — a different sentence on every refresh.
        let raw = SwapError.serverError(message: "failed to simulate swap: pool ETH.FOO-0XDEAD doesn't exist")
        let classifiedFirst: [Error] = [SwapError.noLiquidityPool, raw]
        let classifiedLast: [Error] = [raw, SwapError.noLiquidityPool]
        XCTAssertEqual(SwapService.surfacedQuoteError(from: classifiedFirst) as? SwapError, .noLiquidityPool)
        XCTAssertEqual(SwapService.surfacedQuoteError(from: classifiedLast) as? SwapError, .noLiquidityPool)
    }

    func testRawRelaySurfacesWhenNothingWasClassified() {
        // Nothing better available — the relay is still the only signal, and its
        // message is preserved for the logs.
        let raw = SwapError.serverError(message: "some upstream body")
        XCTAssertEqual(SwapService.surfacedQuoteError(from: [raw]) as? SwapError, raw)
    }

    func testCoreProviderPrecedenceOutranksClassification() {
        // A classified SwapKit error must NOT jump ahead of a core provider's
        // unclassified relay: the SwapKit-is-optional rule is about which
        // provider's opinion is trustworthy, and it still comes first.
        let errors: [Error] = [
            SwapKitError.noRoutesFound,
            SwapError.serverError(message: "core provider body")
        ]
        XCTAssertEqual(
            SwapService.surfacedQuoteError(from: errors) as? SwapError,
            .serverError(message: "core provider body")
        )
    }

    func testRelayLosesToAnyOtherCoreError() {
        // Transport failures are not `SwapError`, but they still carry a verdict
        // of their own, so they outrank the relay.
        let errors: [Error] = [SwapError.serverError(message: "body"), URLError(.timedOut)]
        XCTAssertTrue(SwapService.surfacedQuoteError(from: errors) is URLError)
    }

    func testOnlyTheRelayIsDemoted() {
        // Guard against over-reach: the rule demotes `.serverError` and nothing
        // else. A typed aggregator failure with a specific, actionable message
        // must keep its place in completion order — otherwise a provider that
        // merely answered slower downgrades "Insufficient funds" to the generic
        // "No route available".
        let kyber = KyberSwapError.insufficientFunds(message: "not enough ETH")
        let errors: [Error] = [kyber, SwapError.routeUnavailable]
        XCTAssertTrue(SwapService.surfacedQuoteError(from: errors) is KyberSwapError)
    }

    func testNonSwapErrorCoreFailureStillSurfacesInOrder() {
        // No relay involved at all: completion order is untouched.
        let errors: [Error] = [URLError(.timedOut), SwapError.tradingHalted]
        XCTAssertTrue(SwapService.surfacedQuoteError(from: errors) is URLError)
    }

    // MARK: - Native halt fallback

    func testNativeHaltDoesNotMaskEligibleAggregatorTimeout() {
        let results = [
            SwapProviderQuoteResult(provider: .thorchain, result: .failure(SwapError.tradingHalted)),
            SwapProviderQuoteResult(provider: .lifi, result: .failure(URLError(.timedOut)))
        ]

        let surfaced = SwapService.surfacedProviderQuoteError(from: results)

        XCTAssertTrue(surfaced is URLError)
        XCTAssertNotEqual(surfaced as? SwapError, .tradingHalted)
        XCTAssertEqual(SwapService.transientAggregatorRetryProviders(from: results), [.lifi])
    }

    func testNativeOnlyHaltStillSurfacesHalt() {
        let results = [
            SwapProviderQuoteResult(provider: .thorchain, result: .failure(SwapError.tradingHalted))
        ]

        XCTAssertEqual(SwapService.surfacedProviderQuoteError(from: results) as? SwapError, .tradingHalted)
        XCTAssertTrue(SwapService.transientAggregatorRetryProviders(from: results).isEmpty)
    }

    func testNativeHaltSurfacesWhenEveryAlternativeIsStructurallyUnroutable() {
        let results = [
            SwapProviderQuoteResult(provider: .thorchain, result: .failure(SwapError.tradingHalted)),
            SwapProviderQuoteResult(provider: .lifi, result: .failure(SwapError.routeUnavailable)),
            SwapProviderQuoteResult(provider: .swapkit, result: .failure(SwapKitError.noRoutesFound))
        ]

        XCTAssertEqual(SwapService.surfacedProviderQuoteError(from: results) as? SwapError, .tradingHalted)
        XCTAssertTrue(SwapService.transientAggregatorRetryProviders(from: results).isEmpty)
    }

    @MainActor
    func testTransientAggregatorIsRetriedOnceAndSecondAttemptQuoteWins() async throws {
        let recorder = SwapQuoteAttemptRecorder()
        let service = SwapService(quoteFetcherOverride: { provider in
            try await recorder.fetch(provider)
        })
        let ethereum = makeCoin(.ethereum, ticker: "ETH", decimals: 18)
        let solana = makeCoin(.solana, ticker: "SOL", decimals: 9)

        let quotes = try await service.fetchQuotes(
            amount: 1,
            fromCoin: ethereum,
            toCoin: solana,
            isAffiliate: false,
            referredCode: "",
            vultTierDiscount: 0,
            slippageBps: nil,
            recipientAddress: nil
        )

        let thorAttempts = await recorder.attemptCount(for: .thorchain)
        let liFiAttempts = await recorder.attemptCount(for: .lifi)
        let swapKitAttempts = await recorder.attemptCount(for: .swapkit)
        XCTAssertEqual(quotes.best.kind, .lifi)
        XCTAssertEqual(thorAttempts, 1)
        XCTAssertEqual(liFiAttempts, 2)
        XCTAssertEqual(swapKitAttempts, 1)
    }

    @MainActor
    func testUnsupportedSwapKitTxDoesNotHideLiFiQuote() async throws {
        let service = SwapService(quoteFetcherOverride: { provider in
            switch provider {
            case .swapkit:
                throw SwapKitError.unsupportedTxType("FUTURE_CHAIN")
            case .lifi:
                return .lifi(
                    EVMQuote(
                        dstAmount: "1000000000000000000",
                        tx: EVMQuote.Transaction(
                            from: "0xfrom",
                            to: "0xto",
                            data: "0x",
                            value: "0",
                            gasPrice: "0",
                            gas: 0
                        )
                    ),
                    fee: nil,
                    integratorFee: nil
                )
            default:
                throw SwapError.routeUnavailable
            }
        })
        let ethereum = makeCoin(.ethereum, ticker: "ETH", decimals: 18)
        let robinhood = makeCoin(.robinhood, ticker: "ETH", decimals: 18)

        let quotes = try await service.fetchQuotes(
            amount: 1,
            fromCoin: ethereum,
            toCoin: robinhood,
            isAffiliate: false,
            referredCode: "",
            vultTierDiscount: 0,
            slippageBps: nil,
            recipientAddress: nil
        )

        XCTAssertEqual(quotes.best.kind, .lifi)
        XCTAssertEqual(quotes.ranked.map(\.kind), [.lifi])
    }

    private func makeCoin(_ chain: Chain, ticker: String, decimals: Int) -> Coin {
        let meta = CoinMeta(
            chain: chain,
            ticker: ticker,
            logo: "logo",
            decimals: decimals,
            priceProviderId: ticker.lowercased(),
            contractAddress: "",
            isNativeToken: true
        )
        return Coin(asset: meta, address: "test-address-\(ticker)", hexPublicKey: "")
    }
}

private actor SwapQuoteAttemptRecorder {
    private var attempts: [SwapProvider: Int] = [:]

    func fetch(_ provider: SwapProvider) throws -> SwapQuote {
        attempts[provider, default: 0] += 1

        switch provider {
        case .thorchain:
            throw SwapError.tradingHalted
        case .lifi where attempts[provider] == 1:
            throw URLError(.timedOut)
        case .lifi:
            return .lifi(
                EVMQuote(
                    dstAmount: "1000000000",
                    tx: EVMQuote.Transaction(
                        from: "0xfrom",
                        to: "0xto",
                        data: "0x",
                        value: "0",
                        gasPrice: "0",
                        gas: 0
                    )
                ),
                fee: nil,
                integratorFee: nil
            )
        case .swapkit:
            throw SwapKitError.noRoutesFound
        default:
            throw SwapError.routeUnavailable
        }
    }

    func attemptCount(for provider: SwapProvider) -> Int {
        attempts[provider, default: 0]
    }
}
