//
//  QBTCGovVoteMemo.swift
//  VultisigApp
//
//  Pure builder for the QBTC governance vote memos that `QBTCHelper`
//  consumes. Extracted out of the DeFi view so the memo assembly + weight
//  formatting are unit-testable independent of any SwiftUI surface (the
//  governance vote handlers used to assemble these strings inline, which put
//  business logic in the View).
//
//  The two memo shapes diverge in argument order ON PURPOSE — see the note on
//  each builder. The order is fixed by the QBTC chain's on-chain memo parser
//  (`QBTCHelper.buildMsgVote` / `buildMsgVoteWeighted` decode them), so the
//  asymmetry must be preserved.
//

import Foundation

/// Builds the `QBTC_VOTE:` / `QBTC_VOTEW:` memo strings + their human-facing
/// weight labels. Pure value-in / value-out — no view or service state.
enum QBTCGovVoteMemo {

    /// Single-option vote memo.
    ///
    /// Format: `QBTC_VOTE:<OPTION>:<PROPOSAL_ID>` (option first). This order
    /// differs from the weighted memo (id first) on purpose — it is what the
    /// QBTC on-chain parser expects. Do not realign the two.
    static func singleVote(proposalID: UInt64, choice: CosmosGovVoteChoice) -> String {
        "QBTC_VOTE:\(choice.memoToken):\(proposalID)"
    }

    /// Weighted vote memo.
    ///
    /// Format: `QBTC_VOTEW:<PROPOSAL_ID>:<OPT=W,OPT=W,...>` (id first). The
    /// id-first order here diverges from the single-vote memo on purpose; both
    /// orders are chain-contract-defined. Weights are emitted as plain
    /// decimals (e.g. `0.7`); `QBTCHelper` re-pads them to the canonical
    /// 18-decimal `cosmos.Dec` form.
    static func weightedVote(proposalID: UInt64, options: [CosmosGovVoteOption]) -> String {
        let optionsPart = options
            .map { "\($0.option.memoToken)=\(weightString($0.weight))" }
            .joined(separator: ",")
        return "QBTC_VOTEW:\(proposalID):\(optionsPart)"
    }

    /// Plain decimal string for a weight fraction (e.g. `0.7` -> `"0.7"`), fed
    /// to the memo. `QBTCHelper` re-pads it to the canonical `cosmos.Dec` form.
    static func weightString(_ weight: Decimal) -> String {
        NSDecimalNumber(decimal: weight).stringValue
    }

    /// Percentage label for the verify summary (e.g. `0.7` -> `"70%"`).
    static func weightPercentString(_ weight: Decimal) -> String {
        let percent = NSDecimalNumber(decimal: weight * 100).intValue
        return "\(percent)%"
    }

    /// Comma-joined `"<Option> <pct>%"` summary for the verify screen
    /// (e.g. `"Yes 70%, Abstain 30%"`).
    static func weightedDisplayValue(options: [CosmosGovVoteOption]) -> String {
        options
            .map { "\($0.option.displayTitle) \(weightPercentString($0.weight))" }
            .joined(separator: ", ")
    }
}
