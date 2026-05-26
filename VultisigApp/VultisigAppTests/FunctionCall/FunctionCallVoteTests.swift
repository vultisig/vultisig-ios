//
//  FunctionCallVoteTests.swift
//  VultisigAppTests
//
//  Memo-pin + form-validity + boundary tests for the rewritten
//  `FunctionCallVote` sub-model (DyDx vote memo).
//

import XCTest
@testable import VultisigApp
import WalletCore

@MainActor
final class FunctionCallVoteTests: XCTestCase {

    func testInitProducesEmptyForm() {
        let model = FunctionCallVote()
        XCTAssertEqual(model.selectedMemo, .unspecified)
        XCTAssertEqual(model.proposalID, 0)
        XCTAssertNil(model.customErrorMessage)
    }

    /// Pin: legacy `toString()` returned
    /// `DYDX_VOTE:<voteOption.description>:<proposalID>`.
    func testToStringMatchesLegacyMemo() {
        let model = FunctionCallVote()
        model.selectedMemo = .yes
        model.proposalID = 42
        XCTAssertEqual(model.toString(), "DYDX_VOTE:Yes:42")
    }

    func testToDictionaryMatchesLegacyKeys() {
        let model = FunctionCallVote()
        model.selectedMemo = .no
        model.proposalID = 7
        let dict = model.toDictionary().allItems()
        XCTAssertEqual(dict["VoteDescription"], "No")
        XCTAssertEqual(dict["ProposalId"], "7")
        XCTAssertEqual(dict["memo"], "DYDX_VOTE:No:7")
        XCTAssertEqual(dict.count, 3)
    }

    /// Pin: legacy validation required `memo.rawValue >= 0 && proposalID > 0`.
    /// `.unspecified` rawValue is 0, so it passes the >= 0 check; only
    /// proposalID > 0 actually gates the form.
    func testIsTheFormValidRequiresProposalIDGreaterThanZero() {
        let model = FunctionCallVote()
        XCTAssertFalse(model.isTheFormValid)
        model.proposalID = 1
        XCTAssertTrue(model.isTheFormValid)
    }

    func testToSendTransactionMemoMatchesLegacy() {
        let model = FunctionCallVote()
        model.selectedMemo = .yes
        model.proposalID = 42

        let dyDxCoin = FunctionCallFixture.makeCoin(.dydx, ticker: "DYDX", decimals: 18, isNative: true)
        let vault = FunctionCallFixture.makeVault(coins: [dyDxCoin])

        let tx = model.toSendTransaction(coin: dyDxCoin, vault: vault, gas: 0, isFastVault: false)

        XCTAssertEqual(tx.memo, "DYDX_VOTE:Yes:42")
        XCTAssertEqual(tx.transactionType, .vote)
    }
}
