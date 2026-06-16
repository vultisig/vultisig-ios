//
//  YieldDesign.swift
//  VultisigApp
//

import Foundation
import BigInt

/// Shared layout tokens for the generic yield-vault screens, so the shells don't
/// depend on any one provider's constants.
enum YieldDesign {
    static let horizontalPadding: CGFloat = 20
    static let cardPadding: CGFloat = 16
    static let verticalSpacing: CGFloat = 16
    static let cornerRadius: CGFloat = 16

    #if os(macOS)
    static let mainViewTopPadding: CGFloat = 60
    #else
    static let mainViewTopPadding: CGFloat = 16
    #endif

    static let mainViewBottomPadding: CGFloat = 32
}

/// Decimal ⇄ base-unit conversion shared by the yield forms. Goes through the
/// string form (matching the Circle withdraw path) so floating `Decimal` scaling
/// never produces a fractional remainder.
enum YieldAmount {
    /// Converts a human-readable amount into integer base units. Returns `nil`
    /// (rather than coercing to `0`) when the scaled value doesn't parse, so a
    /// bad conversion can't silently become a zero-amount transaction — callers
    /// must block request construction on `nil`.
    static func baseUnits(_ amount: Decimal, decimals: Int) -> BigInt? {
        let scaled = amount * pow(Decimal(10), decimals)
        let whole = scaled.description.components(separatedBy: ".").first ?? scaled.description
        return BigInt(whole)
    }

    static func humanAmount(_ value: BigInt, decimals: Int) -> Decimal {
        guard let decimal = Decimal(string: value.description) else { return .zero }
        return decimal / pow(Decimal(10), decimals)
    }
}
