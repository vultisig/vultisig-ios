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

    // MARK: - Transaction-type allowlist

    /// Every supported type decodes; a partial decode is never rendered for a
    /// type outside the allowlist.
    func testSupportedTransactionTypesParse() {
        let supported: [String] = [
            "{\"TransactionType\":\"Payment\",\"Account\":\"rAcc\",\"Destination\":\"rDest\",\"Amount\":\"1000000\"}",
            "{\"TransactionType\":\"OfferCreate\",\"Account\":\"rAcc\",\"TakerGets\":\"5000000\",\"TakerPays\":{\"value\":\"10\",\"currency\":\"USD\",\"issuer\":\"rIssuer\"}}",
            "{\"TransactionType\":\"OfferCancel\",\"Account\":\"rAcc\",\"OfferSequence\":42}",
            "{\"TransactionType\":\"TrustSet\",\"Account\":\"rAcc\",\"LimitAmount\":{\"value\":\"1000\",\"currency\":\"USD\",\"issuer\":\"rIssuer\"}}"
        ]
        for json in supported {
            XCTAssertNotNil(parse(json), "expected a supported type to parse: \(json)")
        }
    }

    /// An unsupported type must fail closed even when it carries fields the
    /// decoder knows how to read — rendering a partial card would hide the
    /// security-sensitive terms (RegularKey, SignerEntries, flags) it does not.
    func testUnsupportedTransactionTypeReturnsNil() {
        // SetRegularKey carrying a Destination + Amount: the exact dangerous
        // case where a partial card would look complete while hiding RegularKey.
        XCTAssertNil(parse("""
        {"TransactionType":"SetRegularKey","Account":"rAcc","Destination":"rDest","Amount":"1000000","RegularKey":"rKey"}
        """))
        XCTAssertNil(parse("""
        {"TransactionType":"SignerListSet","Account":"rAcc","SignerQuorum":2}
        """))
        XCTAssertNil(parse("""
        {"TransactionType":"AccountSet","Account":"rAcc","SetFlag":1}
        """))
    }

    // MARK: - Amount validation (over-long drops / non-numeric IOU value)

    /// A drops string one character past the 20-char budget is rejected before
    /// BigInt conversion — pins the off-by-one at the boundary.
    func testOverLongDropsReturnsNil() {
        let justOverBudget = String(repeating: "9", count: 21)
        XCTAssertNil(parse("""
        {"TransactionType":"Payment","Account":"rAcc","Destination":"rDest","Amount":"\(justOverBudget)"}
        """))

        let farOverBudget = String(repeating: "9", count: 40)
        XCTAssertNil(parse("""
        {"TransactionType":"Payment","Account":"rAcc","Destination":"rDest","Amount":"\(farOverBudget)"}
        """))
    }

    /// A drops string exactly at the 20-char budget still parses.
    func testMaxLengthDropsParses() throws {
        // 20 characters — the length budget's upper bound.
        let tx = try XCTUnwrap(parse("""
        {"TransactionType":"Payment","Account":"rAcc","Destination":"rDest","Amount":"10000000000000000000"}
        """))
        XCTAssertEqual(field(tx, "rippleFieldAmount"), .amount(.native(xrp: "10000000000000")))
    }

    /// A non-numeric IOU `value` fails closed.
    func testNonNumericIssuedValueReturnsNil() {
        XCTAssertNil(parse("""
        {"TransactionType":"Payment","Account":"rAcc","Destination":"rDest","Amount":{"value":"abc","currency":"USD","issuer":"rIssuer"}}
        """))
        // A number with trailing garbage is not a valid decimal.
        XCTAssertNil(parse("""
        {"TransactionType":"Payment","Account":"rAcc","Destination":"rDest","Amount":{"value":"10abc","currency":"USD","issuer":"rIssuer"}}
        """))
    }

    // MARK: - TrustSet quality

    /// `QualityIn` / `QualityOut` set the exchange rate applied to balances on
    /// the trust line, so a card showing only `LimitAmount` would look complete
    /// while hiding what the line is worth.
    func testTrustSetQualityRows() throws {
        let tx = try XCTUnwrap(parse("""
        {"TransactionType":"TrustSet","Account":"rAcc","LimitAmount":{"value":"1000","currency":"USD","issuer":"rIssuer"},"QualityIn":900000000,"QualityOut":1100000000}
        """))
        XCTAssertEqual(field(tx, "rippleFieldQualityIn"), .text("900000000"))
        XCTAssertEqual(field(tx, "rippleFieldQualityOut"), .text("1100000000"))
    }

    /// A present-but-undecodable quality fails the decode rather than being
    /// dropped — silently omitting it would hide the rate it sets.
    func testUndecodableQualityReturnsNil() {
        XCTAssertNil(parse("""
        {"TransactionType":"TrustSet","Account":"rAcc","LimitAmount":{"value":"1000","currency":"USD","issuer":"rIssuer"},"QualityIn":"900000000"}
        """))
        XCTAssertNil(parse("""
        {"TransactionType":"TrustSet","Account":"rAcc","LimitAmount":{"value":"1000","currency":"USD","issuer":"rIssuer"},"QualityOut":-1}
        """))
    }

    // MARK: - Flags and Paths

    /// The display half of the acceptance case: `tfPartialPayment` turns the
    /// `Amount` row from a delivery into a ceiling, so the card has to say so.
    func testPartialPaymentPaymentWarns() throws {
        let tx = try XCTUnwrap(parse("""
        {"TransactionType":"Payment","Account":"rAcc","Destination":"rDest","Amount":"1000000","SendMax":"999999999","Flags":131072}
        """))
        XCTAssertEqual(tx.warnings, [.partialPayment])
        XCTAssertEqual(field(tx, "rippleFieldFlags"), .text("tfPartialPayment"))
    }

    /// 0x00020000 is namespace-sensitive — `tfImmediateOrCancel` on an
    /// `OfferCreate`, `tfSetNoRipple` on a `TrustSet`. Neither touches
    /// delivery, so neither may borrow the partial-payment warning, and each
    /// must be named for its own namespace.
    func testPartialPaymentBitOnOtherTypesIsNeitherWarnedNorMislabelled() throws {
        let offer = try XCTUnwrap(parse("""
        {"TransactionType":"OfferCreate","Account":"rAcc","TakerGets":"5000000","TakerPays":{"value":"10","currency":"USD","issuer":"rIssuer"},"Flags":131072}
        """))
        XCTAssertEqual(offer.warnings, [])
        XCTAssertEqual(field(offer, "rippleFieldFlags"), .text("tfImmediateOrCancel"))

        let trustSet = try XCTUnwrap(parse("""
        {"TransactionType":"TrustSet","Account":"rAcc","LimitAmount":{"value":"1000","currency":"USD","issuer":"rIssuer"},"Flags":131072}
        """))
        XCTAssertEqual(trustSet.warnings, [])
        XCTAssertEqual(field(trustSet, "rippleFieldFlags"), .text("tfSetNoRipple"))
    }

    /// `Paths` is surfaced rather than refused, and it does not depend on
    /// `Flags` — a payment can be routed by the site without being partial.
    func testPathsWarns() throws {
        let tx = try XCTUnwrap(parse("""
        {"TransactionType":"Payment","Account":"rAcc","Destination":"rDest","Amount":"1000000","Paths":[[{"currency":"USD","issuer":"rIssuer"}]]}
        """))
        XCTAssertEqual(tx.warnings, [.customPaths])
    }

    /// Both caveats can apply at once, and the partial-payment one leads.
    func testPartialPaymentAndPathsBothWarn() throws {
        let tx = try XCTUnwrap(parse("""
        {"TransactionType":"Payment","Account":"rAcc","Destination":"rDest","Amount":"1000000","Flags":131072,"Paths":[[{"currency":"USD","issuer":"rIssuer"}]]}
        """))
        XCTAssertEqual(tx.warnings, [.partialPayment, .customPaths])
    }

    /// A `Flags` the XRPL codec could not have encoded as a uint32 fails the
    /// whole decode. Reading it as "nothing set" would render a partial payment
    /// as an exact one — the precise mistake this decode exists to prevent.
    func testUndecodableFlagsReturnsNil() {
        let undecodable = [
            "{\"tfPartialPayment\":true}",
            "\"131072\"",
            "true",
            "-1",
            "131072.5",
            "4294967296",
            "null",
            "[131072]"
        ]
        for flags in undecodable {
            XCTAssertNil(parse("""
            {"TransactionType":"Payment","Account":"rAcc","Destination":"rDest","Amount":"1000000","Flags":\(flags)}
            """), "an undecodable Flags must route to the raw-JSON fallback: \(flags)")
        }
    }

    /// `tfFullyCanonicalSig` (0x80000000) is above `INT32_MAX` and applies to
    /// every type, so it must survive the uint32 bound and be named.
    func testFullyCanonicalSigFlagParses() throws {
        let tx = try XCTUnwrap(parse("""
        {"TransactionType":"Payment","Account":"rAcc","Destination":"rDest","Amount":"1000000","Flags":2147483648}
        """))
        XCTAssertEqual(tx.warnings, [])
        XCTAssertEqual(field(tx, "rippleFieldFlags"), .text("tfFullyCanonicalSig"))
    }

    /// A bit this reviewer does not have a name for renders as a hex residue
    /// beside the ones it does, so the row never claims to have shown
    /// everything that is set.
    func testUnknownFlagBitsRenderAsAHexResidue() throws {
        // 0x00060001 = tfPartialPayment | tfLimitQuality | 0x00000001 (unnamed).
        let tx = try XCTUnwrap(parse("""
        {"TransactionType":"Payment","Account":"rAcc","Destination":"rDest","Amount":"1000000","Flags":393217}
        """))
        XCTAssertEqual(
            field(tx, "rippleFieldFlags"),
            .text("tfPartialPayment, tfLimitQuality, 0x00000001")
        )
    }

    /// No flags set, and an absent `Flags`, say the same thing — neither earns
    /// a row.
    func testZeroOrAbsentFlagsAddsNoRow() throws {
        let absent = try XCTUnwrap(parse("""
        {"TransactionType":"Payment","Account":"rAcc","Destination":"rDest","Amount":"1000000"}
        """))
        XCTAssertNil(field(absent, "rippleFieldFlags"))
        XCTAssertEqual(absent.warnings, [])

        let zero = try XCTUnwrap(parse("""
        {"TransactionType":"Payment","Account":"rAcc","Destination":"rDest","Amount":"1000000","Flags":0}
        """))
        XCTAssertNil(field(zero, "rippleFieldFlags"))
        XCTAssertEqual(zero.warnings, [])
    }

    /// Fractional and signed decimal IOU values remain valid.
    func testFractionalAndSignedIssuedValuesParse() throws {
        let fractional = try XCTUnwrap(parse("""
        {"TransactionType":"Payment","Account":"rAcc","Destination":"rDest","Amount":{"value":"0.5","currency":"USD","issuer":"rIssuer"}}
        """))
        XCTAssertEqual(field(fractional, "rippleFieldAmount"), .amount(.issued(value: "0.5", currency: "USD", issuer: "rIssuer")))

        let scientific = try XCTUnwrap(parse("""
        {"TransactionType":"Payment","Account":"rAcc","Destination":"rDest","Amount":{"value":"1e-5","currency":"USD","issuer":"rIssuer"}}
        """))
        XCTAssertEqual(field(scientific, "rippleFieldAmount"), .amount(.issued(value: "1e-5", currency: "USD", issuer: "rIssuer")))

        let signed = try XCTUnwrap(parse("""
        {"TransactionType":"Payment","Account":"rAcc","Destination":"rDest","Amount":{"value":"-1.5","currency":"USD","issuer":"rIssuer"}}
        """))
        XCTAssertEqual(field(signed, "rippleFieldAmount"), .amount(.issued(value: "-1.5", currency: "USD", issuer: "rIssuer")))
    }
}
