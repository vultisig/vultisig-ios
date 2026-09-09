//
//  BasisPointsValidator.swift
//  VultisigApp
//

import Foundation

/// Fails when a non-empty value is not a whole number of basis points in `0...10000`.
///
/// An empty value passes — pair it with `RequiredValidator`, or with whatever
/// cross-field rule decides the field is mandatory.
///
/// ⚠️ **Parses with plain `Int64`, deliberately without trimming.** `IntValidator`
/// trims whitespace; a validator that accepted `" 5"` where the memo builder parses
/// the same string back to `nil` would drop the segment from a memo the user
/// believed carried it. The validator and whatever encodes the value have to agree
/// on what a number is.
struct BasisPointsValidator: FormFieldValidator {

    /// Ten thousand basis points is the whole of whatever the value is a fraction
    /// of. Zero is a legitimate floor — it names the absence of a fee — unlike
    /// `WithdrawBasisPoints.min`, where a withdrawal of nothing asks for nothing.
    static let range: ClosedRange<Int64> = 0...10_000

    let invalidMessage: String
    let outOfRangeMessage: String

    func validate(value: String) throws {
        guard value.isNotEmpty else { return }

        guard let basisPoints = Int64(value) else {
            throw HelperError.runtimeError(invalidMessage)
        }

        guard Self.range.contains(basisPoints) else {
            throw HelperError.runtimeError(outOfRangeMessage)
        }
    }
}
