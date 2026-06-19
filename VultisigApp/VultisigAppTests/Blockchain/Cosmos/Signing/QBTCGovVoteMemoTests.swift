//
//  QBTCGovVoteMemoTests.swift
//  VultisigAppTests
//
//  Unit tests for `QBTCGovVoteMemo`, the pure builder that assembles the
//  `QBTC_VOTE:` / `QBTC_VOTEW:` memos `QBTCHelper` consumes. These were
//  extracted out of `DefiChainMainScreen` so the memo + weight formatting can
//  be exercised independent of any SwiftUI surface. The intentional arg-order
//  divergence between the two memo shapes (option-first vs id-first) is part
//  of the chain contract and is pinned here so a refactor can't silently flip
//  it.
//

@testable import VultisigApp
import XCTest

final class QBTCGovVoteMemoTests: XCTestCase {

    // MARK: - Single vote (option-first)

    func testSingleVoteMemoIsOptionThenId() {
        XCTAssertEqual(
            QBTCGovVoteMemo.singleVote(proposalID: 42, choice: .yes),
            "QBTC_VOTE:YES:42"
        )
        XCTAssertEqual(
            QBTCGovVoteMemo.singleVote(proposalID: 7, choice: .noWithVeto),
            "QBTC_VOTE:NO_WITH_VETO:7"
        )
    }

    // MARK: - Weighted vote (id-first)

    func testWeightedVoteMemoIsIdThenOptions() {
        let memo = QBTCGovVoteMemo.weightedVote(
            proposalID: 42,
            options: [
                CosmosGovVoteOption(option: .yes, weight: Decimal(string: "0.7")!),
                CosmosGovVoteOption(option: .abstain, weight: Decimal(string: "0.3")!)
            ]
        )
        XCTAssertEqual(memo, "QBTC_VOTEW:42:YES=0.7,ABSTAIN=0.3")
    }

    func testWeightedVoteSingleOptionMemo() {
        let memo = QBTCGovVoteMemo.weightedVote(
            proposalID: 1,
            options: [CosmosGovVoteOption(option: .no, weight: Decimal(string: "1")!)]
        )
        XCTAssertEqual(memo, "QBTC_VOTEW:1:NO=1")
    }

    // MARK: - Order divergence guard

    func testSingleAndWeightedMemosDivergeInArgOrder() {
        // Single = option:id, weighted = id:options. The asymmetry is
        // chain-contract-defined; this pins it so it can't be "aligned" away.
        let single = QBTCGovVoteMemo.singleVote(proposalID: 9, choice: .yes)
        let weighted = QBTCGovVoteMemo.weightedVote(
            proposalID: 9,
            options: [CosmosGovVoteOption(option: .yes, weight: Decimal(string: "1")!)]
        )
        XCTAssertTrue(single.hasPrefix("QBTC_VOTE:YES:"))
        XCTAssertTrue(weighted.hasPrefix("QBTC_VOTEW:9:"))
    }

    // MARK: - Weight formatting

    func testWeightStringIsPlainDecimal() {
        XCTAssertEqual(QBTCGovVoteMemo.weightString(Decimal(string: "0.7")!), "0.7")
        XCTAssertEqual(QBTCGovVoteMemo.weightString(Decimal(string: "1")!), "1")
        XCTAssertEqual(QBTCGovVoteMemo.weightString(Decimal(string: "0.333")!), "0.333")
    }

    func testWeightPercentString() {
        XCTAssertEqual(QBTCGovVoteMemo.weightPercentString(Decimal(string: "0.7")!), "70%")
        XCTAssertEqual(QBTCGovVoteMemo.weightPercentString(Decimal(string: "1")!), "100%")
        XCTAssertEqual(QBTCGovVoteMemo.weightPercentString(Decimal(string: "0.05")!), "5%")
    }

    func testWeightedDisplayValueJoinsOptionsWithPercents() {
        let display = QBTCGovVoteMemo.weightedDisplayValue(options: [
            CosmosGovVoteOption(option: .yes, weight: Decimal(string: "0.7")!),
            CosmosGovVoteOption(option: .abstain, weight: Decimal(string: "0.3")!)
        ])
        XCTAssertEqual(display, "\(CosmosGovVoteChoice.yes.displayTitle) 70%, \(CosmosGovVoteChoice.abstain.displayTitle) 30%")
    }
}
