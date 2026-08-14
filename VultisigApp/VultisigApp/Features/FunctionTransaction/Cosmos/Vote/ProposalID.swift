//
//  ProposalID.swift
//  VultisigApp
//
//  Strict parsing for the governance proposal ID the vote memo names.
//
//  A proposal ID is an *identifier*, not an amount, and that is what makes the
//  right answer here different from `SwitchAmount` / `UnmergeShares`. Those
//  have to accept a locale's grouping and decimal separators, because the
//  app's own formatter writes them into the field — and every separator bug
//  found on this migration came from interpreting one (`1,5` read as fifteen,
//  `0,500` read as five hundred, Indian `123,456` off by a thousand).
//
//  An identifier is never grouped and has no fractional part, so this parser
//  reads no separator at all: a run of decimal digits, and nothing else. That
//  makes it locale-independent by construction rather than by care, which is
//  why it takes no `Locale`.
//
//  Digits are not restricted to ASCII. A locale's numbering system may be
//  non-Latin, and refusing `٤٢` would leave those keyboards unable to enter an
//  ID. The test is Unicode's `decimal` numeric type — the set a numbering
//  system uses positionally — which admits `٥` and `५` and rejects `²`, `½`
//  and `Ⅻ`, each of which carries a numeric value that would otherwise fold
//  into a digit and name a different proposal.
//

import Foundation

enum ProposalID {

    /// The proposal ID `text` names, or nil when it is not unambiguously one.
    ///
    /// Rejects: the empty string, anything containing a grouping or decimal
    /// separator, a sign, an exponent, embedded whitespace, and any value that
    /// does not fit the `uint64` the Cosmos gov module uses. Surrounding
    /// whitespace is trimmed. Leading zeros are accepted and normalized —
    /// `007` is proposal 7, unambiguously.
    ///
    /// Zero is returned as `0` rather than refused; the caller's `> 0` gate is
    /// where "there is no proposal 0" is stated, next to the other validity
    /// rules.
    static func parse(_ text: String) -> UInt64? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let digits = decimalDigits(trimmed) else { return nil }
        return UInt64(digits)
    }

    /// `string` rewritten in ASCII digits, or nil if any character is not a
    /// decimal digit.
    private static func decimalDigits(_ string: String) -> String? {
        guard !string.isEmpty else { return nil }
        var result = ""
        result.reserveCapacity(string.count)
        for character in string {
            guard character.unicodeScalars.count == 1,
                  let scalar = character.unicodeScalars.first,
                  scalar.properties.numericType == .decimal,
                  let value = character.wholeNumberValue,
                  (0...9).contains(value) else {
                return nil
            }
            result.append(String(value))
        }
        return result
    }
}
