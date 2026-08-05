//
//  UTXOTransactionPlanErrorTests.swift
//  VultisigAppTests
//
//  WalletCore records WHY it could not plan a transaction. These pin the
//  mapping from that verdict onto a message that names the reason, instead of
//  the blanket "insufficient UTXOs available" every planner failure used to
//  collapse into.
//

import XCTest
import WalletCore
@testable import VultisigApp

final class UTXOTransactionPlanErrorTests: XCTestCase {

    private func plan(_ error: CommonSigningError) -> BitcoinTransactionPlan {
        var plan = BitcoinTransactionPlan()
        plan.error = error
        return plan
    }

    // MARK: - Mapping

    func testOkMapsToNoError() {
        XCTAssertNil(UTXOTransactionPlanError.mapped(.ok))
        XCTAssertNoThrow(try UTXOTransactionPlanError.validate(plan(.ok)))
    }

    func testFundingVerdictsMapToInsufficientFunds() {
        for error in [CommonSigningError.errorLowBalance, .errorNotEnoughUtxos, .errorMissingInputUtxos] {
            XCTAssertEqual(UTXOTransactionPlanError.mapped(error), .insufficientFunds,
                           "\(error) is a funding verdict")
        }
    }

    func testDustVerdictMapsToDustAmount() {
        XCTAssertEqual(UTXOTransactionPlanError.mapped(.errorDustAmountRequested), .dustAmount)
    }

    func testZeroAmountVerdictMapsToZeroAmount() {
        XCTAssertEqual(UTXOTransactionPlanError.mapped(.errorZeroAmountRequested), .zeroAmount)
    }

    func testOversizedVerdictMapsToTransactionTooLarge() {
        XCTAssertEqual(UTXOTransactionPlanError.mapped(.errorTxTooBig), .transactionTooLarge)
    }

    func testUtxoVerdictsMapToInvalidUtxo() {
        XCTAssertEqual(UTXOTransactionPlanError.mapped(.errorInvalidUtxo), .invalidUtxo)
        XCTAssertEqual(UTXOTransactionPlanError.mapped(.errorInvalidUtxoAmount), .invalidUtxo)
    }

    /// A code this build doesn't model — including one a WalletCore upgrade
    /// might add — must still fail, naming the raw code, never pass as success.
    func testUnmodelledVerdictsFallBackToNamedCode() {
        XCTAssertEqual(UTXOTransactionPlanError.mapped(.errorInternal),
                       .planningFailed(code: "errorInternal"))
        XCTAssertEqual(UTXOTransactionPlanError.mapped(.UNRECOGNIZED(9999)),
                       .planningFailed(code: String(describing: CommonSigningError.UNRECOGNIZED(9999))))
    }

    // MARK: - validate(_:)

    func testValidateThrowsTheMappedError() {
        XCTAssertThrowsError(try UTXOTransactionPlanError.validate(plan(.errorDustAmountRequested))) { error in
            XCTAssertEqual(error as? UTXOTransactionPlanError, .dustAmount)
        }
    }

    // MARK: - Messages

    func testEveryCaseHasADistinctLocalizedMessage() {
        let cases: [UTXOTransactionPlanError] = [
            .insufficientFunds, .dustAmount, .zeroAmount,
            .transactionTooLarge, .invalidUtxo, .planningFailed(code: "errorInternal")
        ]
        let messages = cases.map { $0.errorDescription ?? "" }

        for (index, message) in messages.enumerated() {
            XCTAssertFalse(message.isEmpty, "\(cases[index]) must carry a message")
            XCTAssertFalse(message.hasPrefix("utxoPlan"),
                           "\(cases[index]) resolved to its raw key — the string is missing from the catalog")
        }
        XCTAssertEqual(Set(messages).count, messages.count,
                       "each planner verdict must read differently, or the mapping buys nothing")
    }

    func testPlanningFailedMessageNamesTheRawCode() {
        let message = UTXOTransactionPlanError.planningFailed(code: "errorInternal").errorDescription ?? ""
        XCTAssertTrue(message.contains("errorInternal"),
                      "the fallback message must name the code so a bug report can quote it")
    }
}
