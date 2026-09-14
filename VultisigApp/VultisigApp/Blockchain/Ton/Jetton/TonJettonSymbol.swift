//
//  TonJettonSymbol.swift
//  VultisigApp
//

import Foundation

/// Collapses a jetton symbol or name to the Latin skeleton a user actually
/// perceives, so a counterfeit that *reads* as a verified jetton compares equal
/// to it even though it differs byte-for-byte.
///
/// The fake-USDT pattern is the reason this exists: `USD₮`, `UЅDT` (Cyrillic
/// `Ѕ`), `$USĐ₮` and the full-width forms all render as "USDT" to a human, and
/// the counterfeit is distinguishable only by contract address.
enum TonJettonSymbol {

    /// Homoglyphs scammers substitute for Latin capitals. Keys are upper-cased
    /// because the map is applied after `uppercased()`; compatibility
    /// decomposition has already folded the full-width and mathematical forms,
    /// so only characters with no decomposition of their own belong here.
    ///
    /// Deliberately the same table the SDK and Windows use, not a full UTS #39
    /// confusable set: the three platforms have to agree on what counts as a
    /// counterfeit, and a lookalike outside this table simply leaves the jetton
    /// unverified — which never auto-adds either.
    private static let confusables: [Character: Character] = [
        // Cyrillic
        "А": "A", "В": "B", "Е": "E", "Ё": "E", "Ѕ": "S", "І": "I", "Ј": "J",
        "К": "K", "М": "M", "Н": "H", "О": "O", "Р": "P", "С": "C", "Т": "T",
        "У": "Y", "Х": "X", "Ԛ": "Q", "Ԝ": "W",
        // Greek
        "Α": "A", "Β": "B", "Ε": "E", "Ζ": "Z", "Η": "H", "Ι": "I", "Κ": "K",
        "Μ": "M", "Ν": "N", "Ο": "O", "Ρ": "P", "Τ": "T", "Υ": "Y", "Χ": "X",
        // Currency signs and stroked letters
        "₮": "T", "Đ": "D", "Ð": "D", "Ɖ": "D", "Ŧ": "T"
    ]

    /// The skeleton of `value`, or an empty string when nothing survives.
    ///
    /// An empty result must never be treated as a match — every jetton whose
    /// symbol is pure emoji or CJK would otherwise "impersonate" every other
    /// one. Callers index and compare non-empty skeletons only.
    static func normalize(_ value: String) -> String {
        let withoutDiacritics = value
            .decomposedStringWithCompatibilityMapping
            .unicodeScalars
            .filter { $0.properties.generalCategory != .nonspacingMark }

        return String(String.UnicodeScalarView(withoutDiacritics))
            .uppercased()
            .map { confusables[$0] ?? $0 }
            .filter { $0.isASCII && ($0.isNumber || ("A"..."Z").contains($0)) }
            .reduce(into: "") { $0.append($1) }
    }
}
