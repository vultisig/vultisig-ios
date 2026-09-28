//
//  FunctionTransactionReviewSummary.swift
//  VultisigApp
//

import SwiftUI

/// What a DeFi operation's review shows, as text: the amount on its card,
/// the signing vault, and rows that hairlines separate.
struct FunctionTransactionReviewSummary {
    struct Row: Identifiable {
        let label: String
        let value: String
        var image: String?
        var color: Color = Theme.colors.textPrimary
        var isMultiline = false

        var id: String { label }
    }

    /// The amount card: a decoded or resolved hero, or the plain amount.
    let hero: HeroContent
    let vaultName: String
    let vaultAddress: String
    let rows: [Row]
    let fee: (amount: String, fiat: String)
    /// Costs the fee row cannot express, such as a limit cancel's dust.
    let additionalRows: [Row]
}
