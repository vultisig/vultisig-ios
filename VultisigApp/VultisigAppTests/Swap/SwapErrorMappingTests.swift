//
//  SwapErrorMappingTests.swift
//  VultisigAppTests
//
//  Native /quote/swap body-substring → typed SwapError mapping. Halt outranks
//  below-minimum; "zero emit asset" → amount-too-small; pool-missing → no route;
//  the *_trading_paused markers → tradingHalted. Complements the pre-existing
//  SwapServiceTradingHaltedTests (the original two halt markers).
//

import XCTest
@testable import VultisigApp

final class SwapErrorMappingTests: XCTestCase {

    // MARK: - New halt markers (PR-6 additions)

    func testTradingPausedMarkerMapsToTradingHalted() {
        let error = ThorchainSwapError(code: 0, message: "trading paused for this asset")
        XCTAssertEqual(SwapService.mapThorchainSwapError(error).errorDescription, "swapTradingHalted".localized)
    }

    func testUnderscoreTradingPausedMarkerMapsToTradingHalted() {
        // Mirrors the inbound `chain_trading_paused` / `global_trading_paused`
        // flag names leaking into an upstream quote error body.
        let error = MayachainSwapError(code: nil, error: "chain_trading_paused")
        XCTAssertEqual(SwapService.mapMayachainSwapError(error).errorDescription, "swapTradingHalted".localized)
    }

    func testIsPausedMarkerMapsToTradingHalted() {
        let error = ThorchainSwapError(code: 3, message: "the pool is paused")
        XCTAssertEqual(SwapService.mapThorchainSwapError(error).errorDescription, "swapTradingHalted".localized)
    }

    // MARK: - Halt outranks below-minimum

    func testHaltOutranksBelowMinimum() {
        // A body that contains both a halt marker AND a fee/amount marker must
        // map to the halt (the halt check runs first).
        let error = ThorchainSwapError(code: 3, message: "trading paused; not enough asset to pay for fees")
        XCTAssertEqual(SwapService.mapThorchainSwapError(error).errorDescription, "swapTradingHalted".localized)
    }

    // MARK: - zero emit asset → amount too small (PR-6 addition)

    func testZeroEmitAssetMapsToAmountTooSmall() {
        let error = ThorchainSwapError(code: 3, message: "zero emit asset")
        XCTAssertEqual(SwapService.mapThorchainSwapError(error).errorDescription, "swapAmountTooSmall".localized)
    }

    func testZeroEmitAssetCaseInsensitive() {
        let error = ThorchainSwapError(code: 3, message: "Swap produced a ZERO EMIT ASSET")
        XCTAssertEqual(SwapService.mapThorchainSwapError(error).errorDescription, "swapAmountTooSmall".localized)
    }

    // MARK: - Regression guards (unchanged behaviour)

    func testNotEnoughAssetStillMapsToAmountTooSmall() {
        let error = ThorchainSwapError(code: 3, message: "not enough asset to pay for fees")
        XCTAssertEqual(SwapService.mapThorchainSwapError(error).errorDescription, "swapAmountTooSmall".localized)
    }

    func testPoolMissingMapsToNoLiquidityPool() {
        let error = ThorchainSwapError(code: 3, message: "pool does not exist")
        XCTAssertEqual(SwapService.mapThorchainSwapError(error).errorDescription, "noLiquidityPool".localized)
    }

    func testUnknownCode3RelaysServerMessage() {
        let error = ThorchainSwapError(code: 3, message: "totally novel server complaint")
        XCTAssertEqual(SwapService.mapThorchainSwapError(error).errorDescription, "totally novel server complaint")
    }

    func testNonCode3SurfacesServerMessage() {
        // A non-code-3 error with a message must relay that message, not collapse
        // into a generic "route unavailable" — this is what previously hid the
        // secured-asset destination failure (code 2).
        let error = ThorchainSwapError(code: 5, message: "some other upstream failure")
        XCTAssertEqual(SwapService.mapThorchainSwapError(error).errorDescription, "some other upstream failure")
    }

    func testDestinationChainMismatchSurfacesRealMessage() {
        // The exact THORNode rejection for a secured-asset swap with a
        // non-THORChain destination must reach the user/logs verbatim.
        let message = "swap destination address is not the same chain as the target asset"
        let error = ThorchainSwapError(code: 2, message: message)
        XCTAssertEqual(SwapService.mapThorchainSwapError(error).errorDescription, message)
    }

    func testEmptyMessageFallsBackToRouteUnavailable() {
        // With no message to relay there is nothing actionable to show, so the
        // generic route-unavailable fallback is kept.
        let error = ThorchainSwapError(code: 5, message: "")
        XCTAssertEqual(SwapService.mapThorchainSwapError(error).errorDescription, "swapRouteNotAvailable".localized)
    }

    func testMayachainNonHaltRelaysRawMessage() {
        let error = MayachainSwapError(code: 2, error: "maya specific upstream detail")
        XCTAssertEqual(SwapService.mapMayachainSwapError(error).errorDescription, "maya specific upstream detail")
    }

    // MARK: - Maya shares the native classification (no longer leaks as serverError)

    func testMayachainZeroEmitAssetMapsToAmountTooSmall() {
        let error = MayachainSwapError(code: 3, error: "swap produced a zero emit asset")
        XCTAssertEqual(SwapService.mapMayachainSwapError(error).errorDescription, "swapAmountTooSmall".localized)
    }

    func testMayachainPoolMissingMapsToNoLiquidityPool() {
        let error = MayachainSwapError(code: 3, error: "pool does not exist")
        XCTAssertEqual(SwapService.mapMayachainSwapError(error).errorDescription, "noLiquidityPool".localized)
    }

    // MARK: - Price-limit rejection → actionable slippage message

    func testThorchainPriceLimitRejectionMapsToSlippageTooTight() {
        // Verbatim THORNode body captured from a live /quote/swap rejection.
        let error = ThorchainSwapError(
            code: 3,
            message: "failed to simulate swap: failed to simulate handler: emit asset 42579895573 less than price limit 340083366993: invalid request"
        )
        XCTAssertEqual(
            SwapService.mapThorchainSwapError(error).errorDescription,
            "swapSlippageToleranceTooTight".localized
        )
    }

    func testMayachainPriceLimitRejectionMapsToSlippageTooTight() {
        // Verbatim Mayanode body — a shorter shape than THORChain's, which is why
        // the classifier matches the common "less than price limit" substring.
        let error = MayachainSwapError(
            code: 3,
            error: "failed to simulate swap: emit asset 336029740 less than price limit 340582434"
        )
        XCTAssertEqual(
            SwapService.mapMayachainSwapError(error).errorDescription,
            "swapSlippageToleranceTooTight".localized
        )
    }

    func testPriceLimitRejectionIsCaseInsensitive() {
        let error = ThorchainSwapError(code: 3, message: "Emit asset 1 LESS THAN PRICE LIMIT 2")
        XCTAssertEqual(
            SwapService.mapThorchainSwapError(error).errorDescription,
            "swapSlippageToleranceTooTight".localized
        )
    }

    func testPriceLimitRejectionNoLongerLeaksRawNodeString() {
        // Regression guard: this body used to fall through to `.serverError`,
        // showing the untranslated node text verbatim.
        let raw = "failed to simulate swap: emit asset 336029740 less than price limit 340582434"
        let error = MayachainSwapError(code: 3, error: raw)
        XCTAssertNotEqual(SwapService.mapMayachainSwapError(error).errorDescription, raw)
    }

    func testHaltOutranksPriceLimit() {
        // A halted pool that also trips the price-limit check must still surface
        // as the retryable halt message — the halt check runs first.
        let error = ThorchainSwapError(
            code: 3,
            message: "trading is halted: emit asset 1 less than price limit 2"
        )
        XCTAssertEqual(SwapService.mapThorchainSwapError(error).errorDescription, "swapTradingHalted".localized)
    }

    // MARK: - Both nodes' wording for the same missing-pool verdict

    func testThorchainMissingPoolVerbatimBodyMapsToNoLiquidityPool() {
        // Verbatim THORNode body for THOR.RUNE → ETH.VULT (no such pool),
        // captured from gateway.liquify.com/chain/thorchain_api.
        let error = ThorchainSwapError(
            code: 2,
            message: "failed to calculate min swap amount: fail to convert dest fee to src asset pool does not exist"
        )
        XCTAssertEqual(SwapService.mapThorchainSwapError(error), .noLiquidityPool)
    }

    func testMayachainContractedWordingMapsToNoLiquidityPool() {
        // Verbatim Mayanode body for the same pair. MAYAChain contracts the verb
        // where THORChain spells it out, which is why the same verdict used to
        // classify on one chain and leak the raw node string on the other.
        let error = MayachainSwapError(
            code: nil,
            error: "failed to simulate swap: pool ETH.VULT-0XB788144DF611029C60B859DF47E79B7726C4DEBA doesn't exist"
        )
        XCTAssertEqual(SwapService.mapMayachainSwapError(error), .noLiquidityPool)
    }

    func testMayachainContractedWordingNoLongerLeaksTheRawNodeString() {
        let raw = "failed to simulate swap: pool ETH.VULT-0XB788144DF611029C60B859DF47E79B7726C4DEBA doesn't exist"
        let error = MayachainSwapError(code: nil, error: raw)
        XCTAssertNotEqual(SwapService.mapMayachainSwapError(error).errorDescription, raw)
    }

    func testTypographicApostropheAlsoClassifies() {
        let error = MayachainSwapError(code: nil, error: "pool ETH.FOO doesn\u{2019}t exist")
        XCTAssertEqual(SwapService.mapMayachainSwapError(error), .noLiquidityPool)
    }

    func testMissingPoolMatchIsCaseInsensitive() {
        let error = ThorchainSwapError(code: 3, message: "POOL DOES NOT EXIST")
        XCTAssertEqual(SwapService.mapThorchainSwapError(error), .noLiquidityPool)
    }

    func testUnknownThornameIsNotAMissingPool() {
        // The trap the contraction opens up: THORNode uses the same verb for a
        // bad destination address. Verbatim body, captured live. Classifying it
        // as a missing pool would tell the user to pick a different asset when
        // the real fault is the address.
        let message = "bad destination address: unable to parse address: THORName doesn't exist: thor1zf3gsk7edzwl9syyefvfhle37cjtql35h6k85m"
        let error = ThorchainSwapError(code: 2, message: message)
        XCTAssertNotEqual(SwapService.mapThorchainSwapError(error), .noLiquidityPool)
        XCTAssertEqual(SwapService.mapThorchainSwapError(error), .serverError(message: message))
    }

    func testUnrelatedMissingThingIsNotAMissingPool() {
        let error = MayachainSwapError(code: nil, error: "inbound address doesn't exist")
        XCTAssertNotEqual(SwapService.mapMayachainSwapError(error), .noLiquidityPool)
    }

    func testPoolAndMissingVerbInDifferentClausesIsNotAMissingPool() {
        // The pool and the verb have to be in the SAME clause. A composite body
        // that names a pool in one clause and something else missing in another
        // is not a missing-pool verdict — and this classification is load-bearing
        // beyond the tooltip: the limit-order form persists `.noRoute` from it
        // and blocks placement.
        let error = MayachainSwapError(
            code: nil,
            error: "pool ETH.USDC rejected the swap: affiliate THORName doesn't exist"
        )
        XCTAssertNotEqual(SwapService.mapMayachainSwapError(error), .noLiquidityPool)
    }

    // MARK: - Jupiter / LiFi aggregator mapping

    func testJupiterFeeAccountErrorsMapToRouteUnavailable() {
        XCTAssertEqual(SwapService.mapJupiterError(.feeAccountNotProvisioned), .routeUnavailable)
        XCTAssertEqual(SwapService.mapJupiterError(.feeAccountUnavailable), .routeUnavailable)
        XCTAssertEqual(SwapService.mapJupiterError(.invalidQuote), .routeUnavailable)
        XCTAssertEqual(SwapService.mapJupiterError(.quoteFailed(statusCode: 400)), .routeUnavailable)
    }

    func testMappedJupiterErrorIsNotTitledUnexpectedError() {
        let mapped = SwapService.mapJupiterError(.feeAccountNotProvisioned)
        XCTAssertNotEqual(
            SwapErrorPresentation.title(for: mapped),
            SwapCryptoLogic.Errors.unexpectedError.errorTitle
        )
        XCTAssertEqual(
            SwapErrorPresentation.title(for: mapped),
            "swapErrorRouteUnavailableTitle".localized
        )
    }

    func testLiFiNoAvailableQuotesMapsToRouteUnavailable() {
        let error = LiFiSwapError(message: "No available quotes for the requested transfer")
        XCTAssertEqual(SwapService.mapLiFiError(error) as? SwapError, .routeUnavailable)
    }

    func testLiFiOtherBodiesStayLiFiSwapError() {
        let error = LiFiSwapError(message: "rate limited")
        XCTAssertTrue(SwapService.mapLiFiError(error) is LiFiSwapError)
    }
}
