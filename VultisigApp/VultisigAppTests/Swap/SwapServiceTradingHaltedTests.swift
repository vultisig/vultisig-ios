//
//  SwapServiceTradingHaltedTests.swift
//  VultisigAppTests
//
//  Locks the upstream trading-halt detection in SwapService's error mapping.
//  When THORChain or MAYAChain pauses trading for an asset upstream (e.g. a
//  protocol-wide halt after an incident), the quote endpoint returns
//  "trading is halted, can't process swap". That is a temporary, retryable
//  condition — distinct from a permanently unsupported pair — so it must map
//  to the dedicated `.tradingHalted` case (a clean "try again later" message)
//  instead of the generic `.routeUnavailable` (THORChain) or a leaked raw
//  upstream string via `.serverError` (MAYAChain).
//

import XCTest
@testable import VultisigApp

final class SwapServiceTradingHaltedTests: XCTestCase {

    private let haltMessage = "trading is halted, can't process swap"

    // MARK: - Trading halt → .tradingHalted (both providers)

    func testThorchainTradingHaltedMapsToTradingHalted() {
        // THORChain has historically returned the halt on a non-3 code, which
        // previously collapsed to `.routeUnavailable`.
        let error = ThorchainSwapError(code: 0, message: haltMessage)
        let mapped = SwapService.mapThorchainSwapError(error)
        assertTradingHalted(mapped)
    }

    func testThorchainTradingHaltedOnCode3MapsToTradingHalted() {
        // Defensive: if THORChain ever returns the halt under code 3, it must
        // still surface as `.tradingHalted`, not a raw `.serverError`.
        let error = ThorchainSwapError(code: 3, message: haltMessage)
        let mapped = SwapService.mapThorchainSwapError(error)
        assertTradingHalted(mapped)
    }

    func testMayachainTradingHaltedMapsToTradingHalted() {
        // MAYAChain previously leaked this raw string via `.serverError`.
        let error = MayachainSwapError(code: nil, error: haltMessage)
        let mapped = SwapService.mapMayachainSwapError(error)
        assertTradingHalted(mapped)
    }

    func testTradingHaltedDetectionIsCaseInsensitive() {
        let upper = ThorchainSwapError(code: 0, message: "TRADING IS HALTED")
        assertTradingHalted(SwapService.mapThorchainSwapError(upper))

        let alt = MayachainSwapError(code: 1, error: "Trading halted for this asset")
        assertTradingHalted(SwapService.mapMayachainSwapError(alt))
    }

    // MARK: - Regression guards (non-halt errors map as before)

    func testThorchainCode3FeesStillMapsToAmountTooSmall() {
        let error = ThorchainSwapError(code: 3, message: "not enough asset to pay for fees")
        XCTAssertEqual(
            SwapService.mapThorchainSwapError(error).errorDescription,
            "swapAmountTooSmall".localized
        )
    }

    func testThorchainCode3PoolMissingStillMapsToNoLiquidityPool() {
        let error = ThorchainSwapError(code: 3, message: "pool does not exist")
        XCTAssertEqual(
            SwapService.mapThorchainSwapError(error).errorDescription,
            "noLiquidityPool".localized
        )
    }

    func testThorchainNonCode3SurfacesServerMessage() {
        // Non-code-3 errors now relay THORNode's real message instead of
        // collapsing into `.routeUnavailable`, so a specific failure (e.g. the
        // secured-asset "…not the same chain as the target asset" rejection)
        // stays diagnosable. A halt still short-circuits above; only an empty
        // message falls back to route-unavailable.
        let error = ThorchainSwapError(code: 5, message: "some other upstream failure")
        XCTAssertEqual(
            SwapService.mapThorchainSwapError(error).errorDescription,
            "some other upstream failure"
        )
    }

    func testThorchainCode3UnknownStillRelaysServerMessage() {
        let error = ThorchainSwapError(code: 3, message: "totally novel server complaint")
        XCTAssertEqual(
            SwapService.mapThorchainSwapError(error).errorDescription,
            "totally novel server complaint"
        )
    }

    func testMayachainNonHaltStillRelaysRawServerMessage() {
        let error = MayachainSwapError(code: 2, error: "maya specific upstream detail")
        XCTAssertEqual(
            SwapService.mapMayachainSwapError(error).errorDescription,
            "maya specific upstream detail"
        )
    }

    // MARK: - Helper

    private func assertTradingHalted(
        _ error: SwapError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            error.errorDescription,
            "swapTradingHalted".localized,
            "expected .tradingHalted message",
            file: file,
            line: line
        )
        // Guard against the localized lookup silently returning the raw key.
        XCTAssertNotEqual(error.errorDescription, "swapTradingHalted", file: file, line: line)
    }
}
