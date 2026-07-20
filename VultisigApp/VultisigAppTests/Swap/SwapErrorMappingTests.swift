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
}
