//
//  QBTCGovernancePresentation.swift
//  VultisigApp
//
//  View-layer presentation helpers for the QBTC governance tab: status
//  badge title + color, vote-choice tint, the voting-window countdown
//  string, and the message-type-URL short label. Pure formatting — no
//  business logic, no networking.
//

import SwiftUI

extension CosmosGovProposalStatus {
    /// Localized badge title.
    var displayTitle: String {
        switch self {
        case .unspecified: return "governanceStatusUnspecified".localized
        case .depositPeriod: return "governanceStatusDeposit".localized
        case .votingPeriod: return "governanceStatusVoting".localized
        case .passed: return "governanceStatusPassed".localized
        case .rejected: return "governanceStatusRejected".localized
        case .failed: return "governanceStatusFailed".localized
        }
    }

    /// Badge tint — green for passed, red for rejected/failed, accent for an
    /// open vote, muted otherwise.
    var badgeColor: Color {
        switch self {
        case .passed: return Theme.colors.alertSuccess
        case .rejected, .failed: return Theme.colors.alertError
        case .votingPeriod: return Theme.colors.alertInfo
        case .depositPeriod: return Theme.colors.alertWarning
        case .unspecified: return Theme.colors.textTertiary
        }
    }
}

extension CosmosGovVoteChoice {
    /// Tint used for the tally bar segment and the "you voted" badge.
    var tallyColor: Color {
        switch self {
        case .yes: return Theme.colors.alertSuccess
        case .abstain: return Theme.colors.textTertiary
        case .no: return Theme.colors.alertWarning
        case .noWithVeto: return Theme.colors.alertError
        }
    }
}

enum QBTCGovernanceFormat {
    /// Renders the voting-end countdown for an active proposal, e.g.
    /// "Ends in 1d 4h" / "Ends in 12m" / "Voting ended". Returns `nil` when
    /// the proposal has no voting-end time.
    static func votingCountdown(endTime: Date?, now: Date = Date()) -> String? {
        guard let endTime else { return nil }
        let remaining = endTime.timeIntervalSince(now)
        guard remaining > 0 else {
            return "governanceVotingEnded".localized
        }
        return String(format: "governanceVotingEndsIn".localized, shortDuration(remaining))
    }

    /// Compact duration like "1d 4h", "4h 12m", "12m", "<1m" — two units max.
    /// Unit tokens are localized so the countdown reads correctly in every
    /// locale.
    static func shortDuration(_ interval: TimeInterval) -> String {
        let totalMinutes = Int(max(interval, 0) / 60)
        let days = totalMinutes / (60 * 24)
        let hours = (totalMinutes % (60 * 24)) / 60
        let minutes = totalMinutes % 60

        if days > 0 {
            return String(format: "governanceDurationDaysHours".localized, days, hours)
        }
        if hours > 0 {
            return String(format: "governanceDurationHoursMinutes".localized, hours, minutes)
        }
        if minutes > 0 {
            return String(format: "governanceDurationMinutes".localized, minutes)
        }
        return "governanceLessThanOneMinute".localized
    }

    /// Short label for a wrapped message type URL — the trailing
    /// `Msg<Name>`, e.g. `/qbtc.qbtc.v1.MsgGovClaimUTXO` -> "MsgGovClaimUTXO".
    /// Falls back to the full URL when it doesn't split.
    static func messageShortLabel(_ typeURL: String) -> String {
        guard let last = typeURL.split(separator: ".").last, !last.isEmpty else {
            return typeURL
        }
        return String(last)
    }
}
