//
//  AmountPercentageBindingTests.swift
//  VultisigAppTests
//
//  The amount ↔ percentage binding behind every stake / unstake / LP amount
//  field. Typing an amount used to blank the percentage, which left the slider
//  showing its `percentage ?? 100` fallback: a confident 100% under an amount
//  the user had typed as something else entirely.
//

@testable import VultisigApp
import XCTest

final class AmountPercentageBindingTests: XCTestCase {

    private func percentage(_ amount: String, of available: String) -> Double? {
        AmountPercentageBinding.percentage(
            ofAmount: Decimal(string: amount)!,
            available: Decimal(string: available)!
        )
    }

    /// The reported position: 1002.73 typed against 2002.74 staked is a hair
    /// over half, and the slider has to say so rather than claiming 100%.
    func testATypedAmountDerivesItsShareOfTheBalance() throws {
        let derived = try XCTUnwrap(percentage("1002.73", of: "2002.74"))
        XCTAssertEqual(derived, 50.0679, accuracy: 0.0001)
    }

    func testTheWholeBalanceIsAHundredPercent() {
        XCTAssertEqual(percentage("2002.74", of: "2002.74"), 100)
    }

    func testNothingTypedIsZeroPercent() {
        XCTAssertEqual(percentage("0", of: "2002.74"), 0)
    }

    /// The field has to accept an over-balance figure so the balance validator
    /// can report it, but the slider's range is `0...100` — an unclamped
    /// percentage would drive it off its own track.
    func testAnAmountOverTheBalanceClampsToAHundred() {
        XCTAssertEqual(percentage("5000", of: "2002.74"), 100)
    }

    /// No balance is not 0% of something, it is a percentage that does not
    /// exist — and dividing by it would trap.
    func testThereIsNoPercentageOfAnEmptyBalance() {
        XCTAssertNil(percentage("10", of: "0"))
    }

    func testPercentageAndAmountRoundTrip() throws {
        let available = Decimal(string: "2002.74")!
        let derived = try XCTUnwrap(AmountPercentageBinding.percentage(ofAmount: Decimal(string: "500.685")!, available: available))
        let back = AmountPercentageBinding.amount(forPercentage: derived, available: available)
        XCTAssertEqual(NSDecimalNumber(decimal: back).doubleValue, 500.685, accuracy: 0.0001)
    }
}
