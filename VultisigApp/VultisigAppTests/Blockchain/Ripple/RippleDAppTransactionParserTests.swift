//
//  RippleDAppTransactionParserTests.swift
//  VultisigAppTests
//
//  Pins the display-only decode of a dApp-supplied XRPL transaction
//  (`RippleDAppTransaction.parse`): field order, native-drops vs
//  issued-currency amounts, 40-hex currency → ASCII decode, and the
//  fail-closed `nil` fallback on malformed / present-but-undecodable input.
//  Mirrors the Windows `parseRippleTx`.
//

@testable import VultisigApp
import XCTest

final class RippleDAppTransactionParserTests: XCTestCase {

    private func parse(_ json: String) -> RippleDAppTransaction? {
        RippleDAppTransaction.parse(rawJson: json)
    }

    private func field(_ tx: RippleDAppTransaction, _ labelKey: String) -> RippleDAppTransaction.Value? {
        tx.fields.first { $0.labelKey == labelKey }?.value
    }

    // MARK: - Native drops Payment

    func testNativeDropsPayment() throws {
        let tx = try XCTUnwrap(parse("""
        {"TransactionType":"Payment","Account":"rAcc","Destination":"rDest","Amount":"1000000"}
        """))

        XCTAssertEqual(tx.transactionType, "Payment")
        XCTAssertEqual(field(tx, "rippleFieldDestination"), .text("rDest"))
        XCTAssertEqual(field(tx, "rippleFieldAmount"), .amount(.native(xrp: "1")))

        // Field order: Destination precedes Amount.
        XCTAssertEqual(tx.fields.map(\.labelKey), ["rippleFieldDestination", "rippleFieldAmount"])
    }

    func testNativeDropsFractionalXrp() throws {
        let tx = try XCTUnwrap(parse("""
        {"TransactionType":"Payment","Account":"rAcc","Destination":"rDest","Amount":"1500000"}
        """))
        XCTAssertEqual(field(tx, "rippleFieldAmount"), .amount(.native(xrp: "1.5")))
    }

    // MARK: - Cross-currency Payment (issued currency + 40-hex decode)

    func testCrossCurrencyPaymentWithSendMaxAndHexCurrency() throws {
        // Amount is an issued currency whose code is the 40-hex encoding of
        // "TST"; SendMax is native drops. Both must decode, in order.
        let hexTST = "5453540000000000000000000000000000000000"
        let tx = try XCTUnwrap(parse("""
        {"TransactionType":"Payment","Account":"rAcc","Destination":"rDest","Amount":{"value":"10","currency":"\(hexTST)","issuer":"rIssuer"},"SendMax":"2000000"}
        """))

        XCTAssertEqual(tx.transactionType, "Payment")
        XCTAssertEqual(tx.fields.map(\.labelKey), ["rippleFieldDestination", "rippleFieldAmount", "rippleFieldSendMax"])
        XCTAssertEqual(field(tx, "rippleFieldAmount"), .amount(.issued(value: "10", currency: "TST", issuer: "rIssuer")))
        XCTAssertEqual(field(tx, "rippleFieldSendMax"), .amount(.native(xrp: "2")))
    }

    func testStandardCurrencyCodePassthrough() throws {
        let tx = try XCTUnwrap(parse("""
        {"TransactionType":"Payment","Account":"rAcc","Destination":"rDest","Amount":{"value":"42","currency":"USD","issuer":"rIssuer"}}
        """))
        XCTAssertEqual(field(tx, "rippleFieldAmount"), .amount(.issued(value: "42", currency: "USD", issuer: "rIssuer")))
    }

    // MARK: - OfferCreate

    func testOfferCreateTakerGetsAndTakerPays() throws {
        let tx = try XCTUnwrap(parse("""
        {"TransactionType":"OfferCreate","Account":"rAcc","TakerGets":"5000000","TakerPays":{"value":"10","currency":"USD","issuer":"rIssuer"}}
        """))

        XCTAssertEqual(tx.transactionType, "OfferCreate")
        XCTAssertNil(field(tx, "rippleFieldDestination"), "OfferCreate carries no Destination")
        XCTAssertEqual(tx.fields.map(\.labelKey), ["rippleFieldTakerGets", "rippleFieldTakerPays"])
        XCTAssertEqual(field(tx, "rippleFieldTakerGets"), .amount(.native(xrp: "5")))
        XCTAssertEqual(field(tx, "rippleFieldTakerPays"), .amount(.issued(value: "10", currency: "USD", issuer: "rIssuer")))
    }

    // MARK: - Integer metadata fields

    func testDestinationTagRow() throws {
        let tx = try XCTUnwrap(parse("""
        {"TransactionType":"Payment","Account":"rAcc","Destination":"rDest","Amount":"1000000","DestinationTag":12345}
        """))
        XCTAssertEqual(field(tx, "rippleFieldDestinationTag"), .text("12345"))
        // Tag row comes after the amount rows.
        XCTAssertEqual(tx.fields.map(\.labelKey), ["rippleFieldDestination", "rippleFieldAmount", "rippleFieldDestinationTag"])
    }

    func testOfferSequenceRow() throws {
        let tx = try XCTUnwrap(parse("""
        {"TransactionType":"OfferCancel","Account":"rAcc","OfferSequence":42}
        """))
        XCTAssertEqual(field(tx, "rippleFieldOfferSequence"), .text("42"))
    }

    func testTrustSetLimitAmount() throws {
        let tx = try XCTUnwrap(parse("""
        {"TransactionType":"TrustSet","Account":"rAcc","LimitAmount":{"value":"1000","currency":"USD","issuer":"rIssuer"}}
        """))
        XCTAssertEqual(field(tx, "rippleFieldTrustLimit"), .amount(.issued(value: "1000", currency: "USD", issuer: "rIssuer")))
    }

    // MARK: - Malformed / fail-closed → nil

    func testInvalidJsonReturnsNil() {
        XCTAssertNil(parse("not json {{{"))
    }

    func testNonObjectReturnsNil() {
        XCTAssertNil(parse("[1,2,3]"))
    }

    func testMissingTransactionTypeReturnsNil() {
        XCTAssertNil(parse("""
        {"Account":"rAcc","Destination":"rDest","Amount":"1000000"}
        """))
    }

    /// A present Amount that is a JSON number (not a drops string) can't be
    /// decoded → the whole parse fails closed to nil (never hide value behind a
    /// seemingly-complete screen).
    func testPresentButUndecodableNumericAmountReturnsNil() {
        XCTAssertNil(parse("""
        {"TransactionType":"Payment","Account":"rAcc","Destination":"rDest","Amount":123}
        """))
    }

    func testPresentButNonNumericDropsReturnsNil() {
        XCTAssertNil(parse("""
        {"TransactionType":"Payment","Account":"rAcc","Destination":"rDest","Amount":"abc"}
        """))
    }

    func testIssuedAmountMissingValueReturnsNil() {
        XCTAssertNil(parse("""
        {"TransactionType":"Payment","Account":"rAcc","Destination":"rDest","Amount":{"currency":"USD","issuer":"rIssuer"}}
        """))
    }
}
