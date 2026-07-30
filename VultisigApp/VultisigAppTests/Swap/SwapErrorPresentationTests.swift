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

    /// One tag per `SwapError` case. Two exhaustive switches close the loop
    /// around it: `tag(of:)` fails to compile when a case is added to
    /// `SwapError`, and `sample(for:)` fails to compile when a tag is added
    /// here. Adding a case therefore cannot reach `main` without supplying a
    /// sample, and every sample is in `allCases` by construction.
    private enum CaseTag: String, CaseIterable {
        case routeUnavailable
        case recipientRouteUnavailable
        case recipientVerificationFailed
        case noLiquidityPool
        case tradingHalted
        case swapAmountTooSmall
        case slippageToleranceTooTight
        case lessThenMinSwapAmount
        case securedAssetInvalidDestination
        case serverError
    }

    private func sample(for tag: CaseTag) -> SwapError {
        switch tag {
        case .routeUnavailable: return .routeUnavailable
        case .recipientRouteUnavailable: return .recipientRouteUnavailable
        case .recipientVerificationFailed: return .recipientVerificationFailed
        case .noLiquidityPool: return .noLiquidityPool
        case .tradingHalted: return .tradingHalted
        case .swapAmountTooSmall: return .swapAmountTooSmall
        case .slippageToleranceTooTight: return .slippageToleranceTooTight
        case .lessThenMinSwapAmount: return .lessThenMinSwapAmount(amount: "0.01 BTC")
        case .securedAssetInvalidDestination:
            return .securedAssetInvalidDestination(expectedPrefix: "thor", destination: "0xabc")
        case .serverError: return .serverError(message: "some upstream body")
        }
    }

    private func tag(of error: SwapError) -> CaseTag {
        switch error {
        case .routeUnavailable: return .routeUnavailable
        case .recipientRouteUnavailable: return .recipientRouteUnavailable
        case .recipientVerificationFailed: return .recipientVerificationFailed
        case .noLiquidityPool: return .noLiquidityPool
        case .tradingHalted: return .tradingHalted
        case .swapAmountTooSmall: return .swapAmountTooSmall
        case .slippageToleranceTooTight: return .slippageToleranceTooTight
        case .lessThenMinSwapAmount: return .lessThenMinSwapAmount
        case .securedAssetInvalidDestination: return .securedAssetInvalidDestination
        case .serverError: return .serverError
        }
    }

    private var allCases: [SwapError] { CaseTag.allCases.map(sample) }

    /// Localized value for `key`, or `nil` when the key is missing from the
    /// bundle. `"key".localized` echoes the key back on a miss, so asserting
    /// against it proves nothing about the strings file; this does.
    private func localizedValue(forKey key: String) -> String? {
        let sentinel = "__missing_localization__"
        let value = Bundle.main.localizedString(forKey: key, value: sentinel, table: nil)
        return value == sentinel ? nil : value
    }

    // MARK: - The reported bug, through the path the view actually uses

    func testNoLiquidityPoolIsNotTitledUnexpectedError() {
        let generic = SwapCryptoLogic.Errors.unexpectedError.errorTitle
        XCTAssertNotEqual(SwapErrorPresentation.title(for: SwapError.noLiquidityPool), generic)
        XCTAssertEqual(
            SwapErrorPresentation.title(for: SwapError.noLiquidityPool),
            "swapErrorNoLiquidityPoolTitle".localized
        )
        XCTAssertEqual(
            SwapErrorPresentation.message(for: SwapError.noLiquidityPool),
            "noLiquidityPool".localized
        )
    }

    func testResolutionCoversTheThreeVocabulariesTheTooltipMeets() {
        // `SwapError` — the vocabulary that had no title arm at all.
        XCTAssertNotNil(SwapErrorPresentation.presentable(for: SwapError.tradingHalted))
        // `SwapCryptoLogic.Errors` — the vocabulary that always worked.
        XCTAssertNotNil(SwapErrorPresentation.presentable(for: SwapCryptoLogic.Errors.insufficientGas))
        // `SwapKitError` — normalized for the one case with an equivalent.
        XCTAssertEqual(
            SwapErrorPresentation.title(for: SwapKitError.amountBelowProviderMinimum),
            SwapCryptoLogic.Errors.swapAmountTooSmall.errorTitle
        )
    }

    func testUnknownErrorStillFallsBackToItsLocalizedDescription() {
        // Fee-path and transport failures are outside the swap vocabulary. They
        // keep the previous behaviour — generic title, real description — because
        // that description is the only signal they carry.
        let error = NSError(
            domain: "test",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "an unclassifiable failure"]
        )
        XCTAssertEqual(
            SwapErrorPresentation.title(for: error),
            SwapCryptoLogic.Errors.unexpectedError.errorTitle
        )
        XCTAssertEqual(SwapErrorPresentation.message(for: error), "an unclassifiable failure")
    }

    // MARK: - Every case, not just the reported one

    func testNoCaseFallsBackToUnexpectedErrorTitle() {
        let generic = SwapCryptoLogic.Errors.unexpectedError.errorTitle
        for error in allCases {
            XCTAssertNotEqual(
                SwapErrorPresentation.title(for: error),
                generic,
                "\(tag(of: error).rawValue) is still titled generically"
            )
        }
    }

    func testEveryCaseHasNonEmptyTitleAndMessage() {
        for error in allCases {
            XCTAssertFalse(error.errorTitle.isEmpty, "\(tag(of: error).rawValue) has an empty title")
            XCTAssertFalse(error.errorMessage.isEmpty, "\(tag(of: error).rawValue) has an empty message")
        }
    }

    func testTitleKeyPerCase() {
        let expected: [CaseTag: String] = [
            .routeUnavailable: "swapErrorRouteUnavailableTitle",
            .recipientRouteUnavailable: "swapErrorRecipientRouteTitle",
            .recipientVerificationFailed: "swapErrorRecipientVerificationTitle",
            .noLiquidityPool: "swapErrorNoLiquidityPoolTitle",
            .tradingHalted: "swapErrorTradingHaltedTitle",
            // Same verdict as `SwapCryptoLogic.Errors.swapAmountTooSmall`, so the
            // two amount cases deliberately reuse that existing title key.
            .swapAmountTooSmall: "swapErrorAmountTooSmallTitle",
            .lessThenMinSwapAmount: "swapErrorAmountTooSmallTitle",
            .slippageToleranceTooTight: "swapErrorSlippageTooTightTitle",
            .securedAssetInvalidDestination: "swapErrorInvalidDestinationTitle",
            .serverError: "swapErrorProviderRejectedTitle"
        ]
        for error in allCases {
            let name = tag(of: error).rawValue
            guard let key = expected[tag(of: error)] else {
                XCTFail("no expected title key for \(name)")
                continue
            }
            guard let value = localizedValue(forKey: key) else {
                XCTFail("\(key) is missing from Localizable.strings (\(name))")
                continue
            }
            XCTAssertEqual(error.errorTitle, value, "wrong title key for \(name)")
        }
    }

    func testNewCopyKeysExistInTheBundle() {
        // Guards the "missing key leaks a raw camelCase identifier to the user"
        // failure mode that a `"key".localized == "key".localized` assertion
        // cannot see.
        for key in [
            "swapErrorRouteUnavailableTitle",
            "swapErrorRecipientRouteTitle",
            "swapErrorRecipientVerificationTitle",
            "swapErrorNoLiquidityPoolTitle",
            "swapErrorTradingHaltedTitle",
            "swapErrorSlippageTooTightTitle",
            "swapErrorInvalidDestinationTitle",
            "swapErrorProviderRejectedTitle",
            "swapErrorProviderRejectedDescription"
        ] {
            XCTAssertNotNil(localizedValue(forKey: key), "\(key) is missing from Localizable.strings")
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
        // Verbatim MAYAChain body for RUNE → ETH.VULT, captured from
        // mayanode.mayachain.info.
        let raw = "failed to simulate swap: pool ETH.VULT-0XB788144DF611029C60B859DF47E79B7726C4DEBA doesn't exist"
        let error = SwapError.serverError(message: raw)
        XCTAssertNotEqual(SwapErrorPresentation.message(for: error), raw)
        XCTAssertEqual(
            SwapErrorPresentation.message(for: error),
            "swapErrorProviderRejectedDescription".localized
        )
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
        XCTAssertEqual(SwapErrorPresentation.message(for: error), expected)
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
            XCTAssertEqual(SwapErrorPresentation.message(for: error), error.errorDescription)
            XCTAssertEqual(SwapErrorPresentation.title(for: error), error.errorTitle)
            XCTAssertFalse(error.errorTitle.isEmpty)
        }
    }
}
