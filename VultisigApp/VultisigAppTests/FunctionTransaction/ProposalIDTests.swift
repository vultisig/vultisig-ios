//
//  ProposalIDTests.swift
//  VultisigAppTests
//
//  The proposal-ID parse the vote memo is built from. This is the layer four
//  separate defects were found in on the sibling migrations, all of them from
//  *interpreting* a separator: `1,5` read as fifteen, `0,500` read as five
//  hundred, an Indian two-group `123,456` a thousand times off, and ASCII-only
//  digit handling shutting out non-Latin numbering systems.
//
//  A proposal ID is an identifier, so the answer here is to read no separator
//  at all. These tests pin that the refusal is real, and — by driving a
//  `NumberFormatter` in the locales that make each string ambiguous — that the
//  strings being refused are exactly the ones a locale-aware parser would have
//  silently reinterpreted.
//

@testable import VultisigApp
import XCTest

final class ProposalIDTests: XCTestCase {

    // MARK: - Acceptance

    func testPlainDigitsAreAccepted() {
        XCTAssertEqual(ProposalID.parse("1"), 1)
        XCTAssertEqual(ProposalID.parse("42"), 42)
        XCTAssertEqual(ProposalID.parse("1234567"), 1_234_567)
    }

    /// Surrounding whitespace is a paste artifact, not a different number.
    func testSurroundingWhitespaceIsTrimmed() {
        XCTAssertEqual(ProposalID.parse("  42  "), 42)
        XCTAssertEqual(ProposalID.parse("\n42\t"), 42)
    }

    /// `007` is proposal 7 — unambiguously, because there is no separator
    /// convention in which it could be anything else.
    func testLeadingZerosAreNormalized() {
        XCTAssertEqual(ProposalID.parse("007"), 7)
        XCTAssertEqual(ProposalID.parse("0"), 0)
    }

    /// Cosmos gov proposal IDs are `uint64`; the boundary is exact and one past
    /// it is refused rather than truncated.
    func testUInt64BoundaryIsExact() {
        XCTAssertEqual(ProposalID.parse("18446744073709551615"), UInt64.max)
        XCTAssertNil(ProposalID.parse("18446744073709551616"))
        XCTAssertNil(ProposalID.parse("99999999999999999999999999"))
    }

    // MARK: - Rejection

    func testJunkIsRejected() {
        XCTAssertNil(ProposalID.parse(""))
        XCTAssertNil(ProposalID.parse("   "))
        XCTAssertNil(ProposalID.parse("abc"))
        XCTAssertNil(ProposalID.parse("42abc"))
        XCTAssertNil(ProposalID.parse("#42"))
        XCTAssertNil(ProposalID.parse("4 2"))
    }

    /// A sign is not part of an identifier. `+42` would be accepted by
    /// `Int(_:)`, which is what the legacy integer field ultimately used.
    func testSignsAreRejected() {
        XCTAssertNil(ProposalID.parse("-1"))
        XCTAssertNil(ProposalID.parse("+42"))
        XCTAssertNotNil(Int("+42"), "Premise: the obvious parse accepts a sign, which is why this one must not")
    }

    /// Exponents and fractions are not identifiers either.
    func testExponentsAndFractionsAreRejected() {
        XCTAssertNil(ProposalID.parse("4e2"))
        XCTAssertNil(ProposalID.parse("42.0"))
        XCTAssertNil(ProposalID.parse("42,0"))
    }

    /// Characters that carry a numeric value but are not positional digits:
    /// each would otherwise fold into a digit and name a different proposal.
    func testNonPositionalNumeralsAreRejected() {
        XCTAssertNil(ProposalID.parse("²"))
        XCTAssertNil(ProposalID.parse("½"))
        XCTAssertNil(ProposalID.parse("Ⅻ"))
        XCTAssertNil(ProposalID.parse("4²"))
    }

    // MARK: - Non-Latin numbering systems

    /// A locale's numbering system may be non-Latin, and the keyboard emits its
    /// digits. Refusing them would leave those users unable to enter an ID at
    /// all — the ASCII-only defect found on the sibling migrations.
    func testNonLatinDecimalDigitsAreAccepted() {
        XCTAssertEqual(ProposalID.parse("٤٢"), 42, "Arabic-Indic")
        XCTAssertEqual(ProposalID.parse("४२"), 42, "Devanagari")
        XCTAssertEqual(ProposalID.parse("૪૨"), 42, "Gujarati")
    }

    /// Digits from two numbering systems in one string are odd, but not
    /// ambiguous: each scalar is a positional decimal digit with exactly one
    /// value, so `4٢` names 42 and nothing else. Accepted rather than refused —
    /// refusing would need the parser to track which system it is in, which buys
    /// no safety on a value that has one reading, and would diverge from
    /// `HumanDecimalAmount`, whose digit handling this shares.
    func testDigitsFromDifferentNumberingSystemsStillNameOneNumber() {
        XCTAssertEqual(ProposalID.parse("4٢"), 42)
        XCTAssertEqual(ProposalID.parse("४2"), 42)
    }

    // MARK: - Locale independence (the defect class this closes)

    /// Locale-independence is structural here — `parse` takes no `Locale` and
    /// reads none — so what is left to pin is the consequence: every shape whose
    /// meaning *would* depend on one answers nil, and the one shape that does
    /// not answers the same number regardless.
    ///
    /// The locale-specific half is `testStringsALocaleAwareParserWouldAcceptAreRefused`,
    /// which names the locale that makes each of these ambiguous and checks a
    /// formatter in it really does take the string.
    func testEveryShapeWhoseMeaningWouldDependOnALocaleIsRefused() {
        for input in ["1,234", "1.234", "12,34,567", "123,456", "0,500", "1,5", "1 234", "1'234"] {
            XCTAssertNil(ProposalID.parse(input), "\(input) carries a separator and must be refused")
        }
        XCTAssertEqual(ProposalID.parse("1234"), 1234, "The unambiguous spelling is the one that works")
    }

    /// The shapes a locale-aware parser silently *accepts*, each refused here.
    ///
    /// Each is paired with a `NumberFormatter` in the locale that makes it
    /// ambiguous, asserting that the formatter really does take the string
    /// rather than refuse it — the premise is checked rather than described, so
    /// this fails loudly if it ever stops being true. What the formatter
    /// decides the string *means* is exactly the part nobody can rely on, which
    /// is why refusing beats reinterpreting.
    func testStringsALocaleAwareParserWouldAcceptAreRefused() {
        let ambiguous: [(text: String, locale: String, note: String)] = [
            ("1,234", "en_US", "en_US grouping, or a comma-decimal 1.234"),
            ("1.234", "de_DE", "de_DE grouping, or a dot-decimal 1.234"),
            ("1,23,456", "hi_IN", "well-formed Indian grouping — 123456 there, and unreadable anywhere else"),
            ("1,5", "de_DE", "one and a half, which stripping the separator turns into fifteen"),
            ("0,500", "de_DE", "half, whose group widths a naive check reads as five hundred")
        ]

        for sample in ambiguous {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.locale = Locale(identifier: sample.locale)
            XCTAssertNotNil(
                formatter.number(from: sample.text),
                "Premise: \(sample.locale) accepts \(sample.text) — \(sample.note)"
            )
            XCTAssertNil(
                ProposalID.parse(sample.text),
                "\(sample.text) is ambiguous and must be refused, not reinterpreted"
            )
        }
    }

    /// The naive fix — strip the separator, then parse — is what turned `1,5`
    /// into fifteen on a sibling migration. Stated as an assertion so the
    /// alternative this parser rejects is on the record next to it.
    func testStrippingTheSeparatorWouldNameADifferentProposal() {
        XCTAssertEqual(Int("1,5".replacingOccurrences(of: ",", with: "")), 15)
        XCTAssertNil(ProposalID.parse("1,5"))
    }

    /// `1,5` in `de_DE` is one and a half, and in `en_US` it is nothing at all.
    /// Neither is a proposal ID, and neither is silently turned into 15.
    func testACommaDecimalIsNeverFlattenedIntoAnIdentifier() {
        XCTAssertNil(ProposalID.parse("1,5"))
        XCTAssertNil(ProposalID.parse("1.5"))
        XCTAssertNil(ProposalID.parse("0,500"))
    }
}
