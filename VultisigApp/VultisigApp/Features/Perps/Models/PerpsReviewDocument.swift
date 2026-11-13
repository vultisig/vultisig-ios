//
//  PerpsReviewDocument.swift
//  VultisigApp
//
//  What the shared keysign review sheet shows for a perps flow:
//  one big amount, one caption, the few rows needed to decide, one fee total
//  that opens into its breakdown, and the exact requests the vault would sign.
//

import SwiftUI

struct PerpsReviewRow: Identifiable, Sendable {
    enum Tone: Sendable { case normal, positive, negative, warning, muted }

    /// `.vault`: the Vultisig mark and a name on one line, cut at the end.
    enum Style: Sendable { case plain, vault }

    let label: String
    let value: String
    var tone: Tone = .normal
    var style: Style = .plain

    var id: String { label + value }

    var color: Color {
        switch tone {
        case .normal: return Theme.colors.textPrimary
        case .positive: return Theme.colors.alertSuccess
        case .negative: return Theme.colors.alertError
        case .warning: return Theme.colors.alertWarning
        case .muted: return Theme.colors.textTertiary
        }
    }
}

struct PerpsReviewFees: Sendable {
    let total: String
    let breakdown: [PerpsReviewRow]
    /// Details lists the parts under the total: a deposit (several payees) or a VULT discount.
    var showsBreakdown = false
}

struct PerpsReviewDocument: Sendable {
    let sheetTitle: String
    /// Small label above the amount ("Margin").
    var amountLabel: String?
    /// The big number: "$100", "250 USDC".
    let amount: String
    /// Tints the amount (a signed P&L); nil keeps it primary.
    var amountTone: PerpsReviewRow.Tone?
    /// One line under it: "Long BTC · 2×".
    let caption: String
    /// An optional plain sentence under the caption.
    var note: String?
    let coin: String?
    let rows: [PerpsReviewRow]
    var fees: PerpsReviewFees?
    /// Rows at the top of Details, before the fees ("Margin $99.79"): with the
    /// fee total they reconcile the amount entered on the ticket.
    var detailRows: [PerpsReviewRow] = []
    /// Details rows after the fees ("Total from available $100.08").
    var detailTotalRows: [PerpsReviewRow] = []
    /// Rows shown after the fees, such as "You get".
    var trailingRows: [PerpsReviewRow] = []
    /// One quiet line under the rows ("Includes a one-time $1 fee...").
    var footer: String?
    /// The requests at a placeholder nonce, for the review's digests and the
    /// dry-run log. Never signed: signing stamps `steps`.
    let requests: [HLExchangeRequest]
    /// What signing stamps, one at a time, when the user commits
    /// (`HLStamper`): a fresh nonce, an expiry for the signing mode and, for a
    /// market order, a re-quoted price.
    var steps: [HLUnsignedStep] = []
    /// Place-then-cancel exit edits only: the cancel step waits for this.
    var cancelGate: PerpsExitCancelGate?
    /// A CCTP deposit into the trading account (two Arbitrum-side vault signatures).
    var deposit: HLCctpDeposit?
    var blockingIssue: String?
    /// Shown only with `PerpsConfig.showsDebugDetails`.
    var debugNote: String?

    /// Every vault signature this review stands for.
    var signatureCount: Int { requests.count + (deposit == nil ? 0 : 2) }
}
