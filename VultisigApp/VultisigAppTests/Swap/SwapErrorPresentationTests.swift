//
//  SwapErrorPresentationTests.swift
//  VultisigAppTests
//
//  Pins the swap tooltip's title/body resolution. `SwapError` carried correct
//  localized descriptions but no titles, so every one of its cases rendered
//  under the generic "Unexpected Error" heading — a deterministic "no pool for
//  this pair" verdict included.
//

import XCTest
@testable import VultisigApp

final class SwapErrorPresentationTests: XCTestCase {

    /// One value per `SwapError` case. Kept honest by `caseName(_:)` below,
    /// whose exhaustive switch fails to compile when a case is added.
    private let allCases: [SwapError] = [
        .routeUnavailable,
        .recipientRouteUnavailable,
        .recipientVerificationFailed,
        .noLiquidityPool,
        .tradingHalted,
        .swapAmountTooSmall,
        .slippageToleranceTooTight,
        .lessThenMinSwapAmount(amount: "0.01 BTC"),
        .securedAssetInvalidDestination(expectedPrefix: "thor", destination: "0xabc"),
        .serverError(message: "some upstream body")
    ]

    /// Compile-time exhaustiveness guard. A new `SwapError` case breaks this
    /// switch, which forces it into `allCases` and therefore into every
    /// assertion below — including "no case is titled Unexpected Error".
    private func caseName(_ error: SwapError) -> String {
        switch error {
        case .routeUnavailable: return "routeUnavailable"
        case .recipientRouteUnavailable: return "recipientRouteUnavailable"
        case .recipientVerificationFailed: return "recipientVerificationFailed"
        case .noLiquidityPool: return "noLiquidityPool"
        case .tradingHalted: return "tradingHalted"
        case .swapAmountTooSmall: return "swapAmountTooSmall"
        case .slippageToleranceTooTight: return "slippageToleranceTooTight"
        case .lessThenMinSwapAmount: return "lessThenMinSwapAmount"
        case .securedAssetInvalidDestination: return "securedAssetInvalidDestination"
        case .serverError: return "serverError"
        }
    }

    // MARK: - The reported bug

    func testNoLiquidityPoolIsNotTitledUnexpectedError() {
        XCTAssertNotEqual(
            SwapError.noLiquidityPool.errorTitle,
            SwapCryptoLogic.Errors.unexpectedError.errorTitle
        )
        XCTAssertEqual(SwapError.noLiquidityPool.errorTitle, "swapErrorNoLiquidityPoolTitle".localized)
        XCTAssertEqual(SwapError.noLiquidityPool.errorMessage, "noLiquidityPool".localized)
    }

    // MARK: - Every case, not just the reported one

    func testEveryCaseCoveredExactlyOnce() {
        let names = allCases.map(caseName)
        XCTAssertEqual(Set(names).count, names.count, "duplicate sample in allCases")
        XCTAssertEqual(names.count, 10, "a SwapError case is missing from allCases")
    }

    func testNoCaseFallsBackToUnexpectedErrorTitle() {
        let generic = SwapCryptoLogic.Errors.unexpectedError.errorTitle
        for error in allCases {
            XCTAssertNotEqual(error.errorTitle, generic, "\(caseName(error)) is still titled generically")
        }
    }

    func testEveryCaseHasNonEmptyTitleAndMessage() {
        for error in allCases {
            XCTAssertFalse(error.errorTitle.isEmpty, "\(caseName(error)) has an empty title")
            XCTAssertFalse(error.errorMessage.isEmpty, "\(caseName(error)) has an empty message")
        }
    }

    func testTitleKeyPerCase() {
        let expected: [String: String] = [
            "routeUnavailable": "swapErrorRouteUnavailableTitle",
            "recipientRouteUnavailable": "swapErrorRecipientRouteTitle",
            "recipientVerificationFailed": "swapErrorRecipientVerificationTitle",
            "noLiquidityPool": "swapErrorNoLiquidityPoolTitle",
            "tradingHalted": "swapErrorTradingHaltedTitle",
            // Same verdict as `SwapCryptoLogic.Errors.swapAmountTooSmall`, so the
            // two amount cases deliberately reuse that existing title key.
            "swapAmountTooSmall": "swapErrorAmountTooSmallTitle",
            "lessThenMinSwapAmount": "swapErrorAmountTooSmallTitle",
            "slippageToleranceTooTight": "swapErrorSlippageTooTightTitle",
            "securedAssetInvalidDestination": "swapErrorInvalidDestinationTitle",
            "serverError": "swapErrorProviderRejectedTitle"
        ]
        for error in allCases {
            guard let key = expected[caseName(error)] else {
                XCTFail("no expected title key for \(caseName(error))")
                continue
            }
            XCTAssertEqual(error.errorTitle, key.localized, "wrong title key for \(caseName(error))")
        }
    }

    func testAmountCasesShareTheExistingAmountTitle() {
        XCTAssertEqual(
            SwapError.swapAmountTooSmall.errorTitle,
            SwapCryptoLogic.Errors.swapAmountTooSmall.errorTitle
        )
        XCTAssertEqual(
            SwapError.lessThenMinSwapAmount(amount: "0.01 BTC").errorTitle,
            SwapCryptoLogic.Errors.swapAmountTooSmall.errorTitle
        )
    }

    // MARK: - Raw upstream text never reaches the tooltip body

    func testServerErrorMessageIsGenericNotTheProviderString() {
        let raw = "failed to simulate swap: pool ETH.VULT-0XB788144DF611029C60B859DF47E79B7726C4DEBA doesn't exist"
        let error = SwapError.serverError(message: raw)
        XCTAssertNotEqual(error.errorMessage, raw)
        XCTAssertEqual(error.errorMessage, "swapErrorProviderRejectedDescription".localized)
    }

    func testServerErrorKeepsTheProviderStringForLogs() {
        // `errorDescription` is the diagnostic channel (`localizedDescription`,
        // logger lines). It must keep the provider's own wording so a support
        // log still explains what upstream actually said.
        let raw = "failed to simulate swap: pool ETH.VULT-0X… doesn't exist"
        XCTAssertEqual(SwapError.serverError(message: raw).errorDescription, raw)
    }

    // MARK: - The secured-asset guard keeps its app-authored copy

    func testSecuredAssetInvalidDestinationKeepsFormattedAppCopy() {
        let error = SwapError.securedAssetInvalidDestination(expectedPrefix: "thor", destination: "0xdead")
        let expected = String(format: "swapSecuredAssetInvalidDestination".localized, "thor", "0xdead")
        XCTAssertEqual(error.errorDescription, expected)
        // It is app copy, so unlike `serverError` it is shown verbatim.
        XCTAssertEqual(error.errorMessage, expected)
    }

    // MARK: - SwapCryptoLogic.Errors keeps its existing presentation

    func testSwapCryptoLogicErrorsMessageMatchesItsDescription() {
        for error in [
            SwapCryptoLogic.Errors.unexpectedError,
            .insufficientFunds,
            .insufficientGas,
            .swapAmountTooSmall,
            .inboundAddress,
            .sameAsset
        ] {
            XCTAssertEqual(error.errorMessage, error.errorDescription)
            XCTAssertFalse(error.errorTitle.isEmpty)
        }
    }
}
