//
//  TransactionHistoryCardViewTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

final class TransactionHistoryCardViewTests: XCTestCase {
    func testCompletedTransactionsNeverExpand() {
        for status in [TransactionHistoryStatus.successful, .error] {
            XCTAssertFalse(TransactionHistoryCardView.shouldExpand(status: status, type: .send))
            XCTAssertFalse(TransactionHistoryCardView.shouldExpand(status: status, type: .swap))
            XCTAssertFalse(TransactionHistoryCardView.shouldExpand(status: status, type: .approve))
        }
    }

    func testInProgressTransactionExpandsUnlessItIsApproval() {
        XCTAssertTrue(TransactionHistoryCardView.shouldExpand(status: .inProgress, type: .send))
        XCTAssertTrue(TransactionHistoryCardView.shouldExpand(status: .inProgress, type: .swap))
        XCTAssertFalse(TransactionHistoryCardView.shouldExpand(status: .inProgress, type: .approve))
    }
}
