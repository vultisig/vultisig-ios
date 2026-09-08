//
//  TransactionHistoryFailureReasonPresentationTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

final class TransactionHistoryFailureReasonPresentationTests: XCTestCase {
    func testReturnAmountIsNotEnoughUsesSlippageGuidance() {
        XCTAssertEqual(
            TransactionHistoryFailureReasonPresentation.displayText(for: "Return amount is not enough"),
            "swapSlippageToleranceTooTight".localized
        )
    }

    func testInsufficientOutputUsesSlippageGuidance() {
        XCTAssertEqual(
            TransactionHistoryFailureReasonPresentation.displayText(for: "Insufficient output"),
            "swapSlippageToleranceTooTight".localized
        )
    }

    func testReturnAmountSignatureMatchesInsideWrapperText() {
        XCTAssertEqual(
            TransactionHistoryFailureReasonPresentation.displayText(
                for: "RPC error: RETURN AMOUNT IS NOT ENOUGH [code 3]"
            ),
            "swapSlippageToleranceTooTight".localized
        )
    }

    func testMatchingIsCaseInsensitiveInsideWrapperText() {
        XCTAssertEqual(
            TransactionHistoryFailureReasonPresentation.displayText(
                for: "execution reverted: INSUFFICIENT OUTPUT while routing"
            ),
            "swapSlippageToleranceTooTight".localized
        )
    }

    func testUnknownReasonPassesThroughUnchanged() {
        let rawReason = "  execution reverted: transfer failed  "

        XCTAssertEqual(
            TransactionHistoryFailureReasonPresentation.displayText(for: rawReason),
            rawReason
        )
    }

    func testNilAndEmptyReasonsAreSuppressed() {
        XCTAssertNil(TransactionHistoryFailureReasonPresentation.displayText(for: nil))
        XCTAssertNil(TransactionHistoryFailureReasonPresentation.displayText(for: ""))
    }
}
