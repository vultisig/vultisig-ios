//
//  ExternalAmountGuardTests.swift
//  VultisigAppTests
//
//  Amounts that reach the send form from outside the app — a `vultisig://send`
//  deeplink and a scanned `bitcoin:` / `ton://` URI — must be plain decimals
//  before they can be prefilled. `NumberFormatter` expands scientific notation,
//  so an unguarded `amount=1e5` stages 100000.
//

import XCTest
@testable import VultisigApp

@MainActor
final class ExternalAmountGuardTests: XCTestCase {

    // MARK: - Why the guard rejects rather than normalises

    /// Verify renders the amount string verbatim — `SendVerifyScreen` hands
    /// `tx.amount` to `CoinAmountFiatLabel`, which is a plain `Text(amount)` with
    /// no formatting hop — while everything signed derives from `amountDecimal`.
    /// For scientific notation those two disagree by five orders of magnitude.
    func testScientificNotationDisplaysAndSignsDifferentValues() {
        let coin = SendFormFixture.makeBTC()
        let displayed = "1e5"

        let signed = SendCryptoLogic.amountDecimal(coin: coin, amount: displayed)

        XCTAssertEqual(signed, Decimal(100_000))
        XCTAssertNotEqual(displayed, "\(signed)")
        XCTAssertFalse(displayed.isValidDecimal(), "the form must refuse it before Verify can show it")
    }

    // MARK: - Deeplink boundary

    private func sendAmount(from query: String) throws -> String? {
        let url = URL(string: "vultisig://send?assetChain=ethereum&assetTicker=ETH&toAddress=0xdead&\(query)")!
        return try DeeplinkLogic().extractParameters(url, vaults: []).sendAmount
    }

    func testDeeplinkDropsScientificNotationAmount() throws {
        XCTAssertNil(try sendAmount(from: "amount=1e5"))
        XCTAssertNil(try sendAmount(from: "amount=1E5"))
        XCTAssertNil(try sendAmount(from: "amount=2.5e3"))
        XCTAssertNil(try sendAmount(from: "amount=1e-3"))
        XCTAssertNil(try sendAmount(from: "amount=0x1F"))
    }

    func testDeeplinkKeepsPlainDecimalAmount() throws {
        XCTAssertEqual(try sendAmount(from: "amount=1.5"), "1.5")
        XCTAssertEqual(try sendAmount(from: "amount=0.00000001"), "0.00000001")
        XCTAssertEqual(try sendAmount(from: "amount=100000"), "100000")
    }

    /// A link with no amount at all is unchanged by the guard — the form opens
    /// with an empty field, exactly as a rejected one now does.
    func testDeeplinkWithoutAmountStaysNil() throws {
        XCTAssertNil(try sendAmount(from: "memo=hello"))
    }

    /// The rest of the send deeplink keeps working when the amount is dropped:
    /// the address still routes, so the user lands on a prefilled form and types
    /// the amount themselves.
    func testDeeplinkWithRejectedAmountStillCarriesAddress() throws {
        let url = URL(string: "vultisig://send?assetChain=ethereum&assetTicker=ETH&toAddress=0xdead&amount=1e5")!

        let result = try DeeplinkLogic().extractParameters(url, vaults: [])

        XCTAssertEqual(result.address, "0xdead")
        XCTAssertEqual(result.type, .Send)
        XCTAssertNil(result.sendAmount)
    }

    // MARK: - Scanned crypto-URI boundary

    func testScannedURIDropsScientificNotationAmount() {
        XCTAssertNil(AddressResult.fromURI("bitcoin:bc1qexampleaddress?amount=1e5").amount)
        XCTAssertNil(AddressResult.fromURI("bitcoin:bc1qexampleaddress?amount=2.5e3").amount)
        XCTAssertNil(AddressResult.fromURI("ton://transfer/EQabc?amount=1e5").amount)
    }

    func testScannedURIKeepsPlainDecimalAmount() {
        XCTAssertEqual(AddressResult.fromURI("bitcoin:bc1qexampleaddress?amount=0.5").amount, "0.5")
        XCTAssertEqual(AddressResult.fromURI("ton://transfer/EQabc?amount=12.25").amount, "12.25")
    }

    /// Dropping the amount must not drop the address or the memo riding with it.
    func testScannedURIWithRejectedAmountKeepsAddressAndMessage() {
        let result = AddressResult.fromURI("bitcoin:bc1qexampleaddress?amount=1e5&message=coffee")

        XCTAssertEqual(result.address, "bc1qexampleaddress")
        XCTAssertEqual(result.memo, "coffee")
        XCTAssertNil(result.amount)
    }
}
