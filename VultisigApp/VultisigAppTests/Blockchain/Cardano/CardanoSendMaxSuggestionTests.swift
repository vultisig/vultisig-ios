//
//  CardanoSendMaxSuggestionTests.swift
//  VultisigAppTests
//
//  Pins the ADA amount quoted by the three validation messages that suggest
//  "Send Max". They must quote what Max would ACTUALLY send — balance minus
//  fee, matching `SendCryptoLogic.computeMaxAmount` — not the raw balance.
//  Quoting the balance advertises more ADA than Max can deliver, which is a
//  promise the very next tap breaks.
//
//  Also pins ADA's full 6-decimal precision: an earlier `decimals - 1` shave
//  quoted less than Max sends, the mirror-image lie.
//
//  Expected strings are built through the same `formatToDecimal` the production
//  code uses, so these assertions hold on comma-decimal locales too.
//

@testable import VultisigApp
import BigInt
import XCTest

final class CardanoSendMaxSuggestionTests: XCTestCase {

    private let oneADA = BigInt(1_000_000)

    /// Renders lovelaces the way the validation messages do.
    private func ada(_ lovelaces: BigInt) -> String {
        lovelaces.toADA.formatToDecimal(digits: 6)
    }

    // MARK: - Insufficient-balance path

    func testInsufficientBalanceQuotesMaxNetOfFee() throws {
        // 10 ADA balance, 0.5 ADA fee → Max sends 9.5, not 10.
        let balance = oneADA * 10
        let fee = BigInt(500_000)
        let result = CardanoHelper.validateUTXORequirements(
            sendAmount: BigInt(9_900_000),
            totalBalance: balance,
            estimatedFee: fee
        )

        XCTAssertFalse(result.isValid)
        let message = try XCTUnwrap(result.errorMessage)
        XCTAssertTrue(
            message.contains(ada(balance - fee)),
            "expected fee-adjusted \(ada(balance - fee)), got: \(message)"
        )
        XCTAssertFalse(
            message.contains("\(ada(balance)) ADA"),
            "must not advertise the raw balance \(ada(balance)): \(message)"
        )
    }

    // MARK: - Change-too-small path

    func testTooLittleChangeQuotesMaxNetOfFee() throws {
        // 5 ADA balance, 0.17 ADA fee, sending 3.9 → change 0.93 (< 1.4 minUTXO).
        let balance = oneADA * 5
        let fee = BigInt(170_000)
        let result = CardanoHelper.validateUTXORequirements(
            sendAmount: BigInt(3_900_000),
            totalBalance: balance,
            estimatedFee: fee
        )

        XCTAssertFalse(result.isValid)
        let message = try XCTUnwrap(result.errorMessage)
        XCTAssertTrue(
            message.contains(ada(balance - fee)),
            "expected \(ada(balance - fee)), got: \(message)"
        )
    }

    // MARK: - Low-balance recommendation

    func testLowBalanceRecommendationQuotesMaxNetOfFee() throws {
        // 3 ADA balance (under the 3.5 threshold), 0.17 ADA fee → 2.83.
        let balance = oneADA * 3
        let fee = BigInt(170_000)
        let result = CardanoHelper.shouldRecommendSendMax(
            totalBalance: balance,
            estimatedFee: fee
        )

        XCTAssertTrue(result.shouldRecommend)
        let message = try XCTUnwrap(result.message)
        XCTAssertTrue(
            message.contains(ada(balance - fee)),
            "expected \(ada(balance - fee)), got: \(message)"
        )
    }

    // MARK: - Precision

    func testSuggestionKeepsAllSixAdaDecimals() throws {
        // 3.123456 balance, 1 lovelace fee → 3.123455, exercising the 6th
        // decimal. A `decimals - 1` shave would quote 3.12345 and strand a digit.
        let balance = BigInt(3_123_456)
        let fee = BigInt(1)
        let result = CardanoHelper.shouldRecommendSendMax(
            totalBalance: balance,
            estimatedFee: fee
        )

        XCTAssertTrue(result.shouldRecommend)
        let message = try XCTUnwrap(result.message)
        // A shaved quote (3.12345) cannot contain the full 6-decimal string,
        // so the positive assertion alone pins the precision. Asserting the
        // absence of "3.12345" would not work — it is a prefix of "3.123455".
        let expected = ada(balance - fee)
        XCTAssertTrue(message.contains(expected), "expected full-precision \(expected), got: \(message)")
    }

    // MARK: - Guards

    func testFeeExceedingBalanceDoesNotRecommendSendMax() {
        // Below the fee there is nothing to suggest; the suggestion path must
        // not be reached with a negative max.
        let result = CardanoHelper.shouldRecommendSendMax(
            totalBalance: BigInt(100_000),
            estimatedFee: BigInt(170_000)
        )

        XCTAssertFalse(result.shouldRecommend)
        XCTAssertNil(result.message)
    }
}
