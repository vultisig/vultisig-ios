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
}
