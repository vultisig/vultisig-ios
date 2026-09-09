//
//  TonJettonSymbolTests.swift
//  VultisigAppTests
//
//  The counterfeit-USDT skeletons this has to fold. Every spelling below was
//  taken from a jetton that ships in Tonkeeper's `ton-assets` whitelist or from
//  the impersonation patterns the SDK sampled; the real Tether jetton itself is
//  listed as `USD₮`, so folding is what lets it compare equal to our curated
//  `USDT` entry at all.
//

import XCTest
@testable import VultisigApp

final class TonJettonSymbolTests: XCTestCase {

    func testFoldsTugrikSignOntoUSDT() {
        XCTAssertEqual(TonJettonSymbol.normalize("USD₮"), "USDT")
    }

    func testFoldsCyrillicHomoglyphOntoUSDT() {
        // U+0405 CYRILLIC CAPITAL LETTER DZE, not U+0053 LATIN CAPITAL S.
        XCTAssertEqual(TonJettonSymbol.normalize("UЅDT"), "USDT")
    }

    func testFoldsStrokedLetterAndPunctuationOntoUSDT() {
        XCTAssertEqual(TonJettonSymbol.normalize("$USĐ₮"), "USDT")
    }

    func testFoldsFullWidthFormsOntoUSDT() {
        XCTAssertEqual(TonJettonSymbol.normalize("ＵＳＤＴ"), "USDT")
    }

    func testFoldsCaseOntoUSDT() {
        XCTAssertEqual(TonJettonSymbol.normalize("usdt"), "USDT")
    }

    /// Every spelling above has to reach the same skeleton, or an impersonator
    /// only matches the one variant the test happened to name.
    func testAllUSDTSpellingsShareOneSkeleton() {
        let spellings = ["USDT", "USD₮", "UЅDT", "$USĐ₮", "ＵＳＤＴ", "usdt", "  usd₮  "]
        XCTAssertEqual(Set(spellings.map(TonJettonSymbol.normalize)), ["USDT"])
    }

    func testFoldsGreekHomoglyph() {
        // U+0399 GREEK CAPITAL LETTER IOTA in place of Latin I.
        XCTAssertEqual(TonJettonSymbol.normalize("ΒΙΤ"), "BIT")
    }

    func testStripsDiacritics() {
        XCTAssertEqual(TonJettonSymbol.normalize("Café"), "CAFE")
        XCTAssertEqual(TonJettonSymbol.normalize("HOLÐ"), "HOLD")
    }

    func testNamesFoldTheSameWayAsSymbols() {
        XCTAssertEqual(TonJettonSymbol.normalize("Tether USD"), "TETHERUSD")
    }

    func testDropsSeparatorsAndKeepsDigits() {
        XCTAssertEqual(TonJettonSymbol.normalize("USD₮-BEHT LP"), "USDTBEHTLP")
        XCTAssertEqual(TonJettonSymbol.normalize("$80"), "80")
    }

    /// Characters the table does not map are dropped, which cuts both ways and
    /// is a deliberate choice rather than an oversight.
    ///
    /// Dropping is what defeats padding: an appended Cyrillic letter, or an
    /// invisible zero-width space spliced into the middle, cannot buy a
    /// counterfeit a different skeleton. The cost is the mirror case — a
    /// homoglyph outside the table (Armenian `Ս` standing in for `U` here)
    /// survives the mapping step, is then dropped as non-ASCII, and the
    /// impersonation is missed.
    ///
    /// The table is deliberately the SDK's, so iOS, Windows and the SDK agree on
    /// what counts as a counterfeit; widening it here alone would make one
    /// jetton read `scam` on one platform and `unverified` on another. The
    /// safety property does not rest on it either way: a missed fold leaves an
    /// unlisted jetton `unverified`, which never auto-adds.
    func testUnmappedCharactersAreDroppedInBothDirections() {
        XCTAssertEqual(TonJettonSymbol.normalize("USDT\u{0416}"), "USDT", "padding cannot escape the skeleton")
        XCTAssertEqual(TonJettonSymbol.normalize("US\u{200B}DT"), "USDT", "nor can an invisible character")
        XCTAssertEqual(TonJettonSymbol.normalize("\u{054D}SDT"), "SDT", "known gap: Armenian S-lookalike is unmapped")
    }

    /// A symbol with no Latin skeleton must normalize to empty rather than to
    /// something that collides. Callers treat empty as "never matches"; if this
    /// returned a partial skeleton instead, every CJK- or emoji-named jetton
    /// would impersonate whatever it collapsed onto.
    func testSymbolsWithNoLatinSkeletonNormalizeToEmpty() {
        XCTAssertEqual(TonJettonSymbol.normalize("道德經"), "")
        XCTAssertEqual(TonJettonSymbol.normalize("🅿️"), "")
        XCTAssertEqual(TonJettonSymbol.normalize(""), "")
        XCTAssertEqual(TonJettonSymbol.normalize("   "), "")
    }
}
