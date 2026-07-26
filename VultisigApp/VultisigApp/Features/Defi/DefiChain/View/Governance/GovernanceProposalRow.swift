//
//  GovernanceProposalRow.swift
//  VultisigApp
//
//  One proposal card in the QBTC governance list: id + title, status badge,
//  the voting-end countdown (active only), a compact tally bar, and the
//  "you voted X" badge when the user has a recorded vote. Tapping the card
//  opens the detail.
//

import SwiftUI

struct GovernanceStatusBadge: View {
    let status: CosmosGovProposalStatus

    var body: some View {
        Text(status.displayTitle)
            .font(Theme.fonts.caption12)
            .foregroundStyle(status.badgeColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(status.badgeColor.opacity(0.12))
            )
    }
}

struct GovernanceMyVoteBadge: View {
    let choice: CosmosGovVoteChoice

    var body: some View {
        HStack(spacing: 4) {
            Icon(.check, color: choice.tallyColor, size: 12)
            Text(String(format: "governanceYouVoted".localized, choice.displayTitle))
                .font(Theme.fonts.caption12)
                .foregroundStyle(choice.tallyColor)
        }
    }
}

struct GovernanceProposalRow: View {
    let proposal: CosmosGovProposal
    let tally: CosmosGovTallyResult
    let myVote: CosmosGovVote?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                header
                if !proposal.summary.isEmpty {
                    Text(proposal.summary)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                GovernanceTallyBar(tally: tally)
                footer
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Theme.colors.bgSurface1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Theme.colors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: "governanceProposalNumber".localized, String(proposal.id)))
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
                Text(proposal.title.isEmpty ? "governanceUntitledProposal".localized : proposal.title)
                    .font(Theme.fonts.bodyMMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 8)
            GovernanceStatusBadge(status: proposal.status)
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 8) {
            if let choice = myVote?.primaryChoice {
                GovernanceMyVoteBadge(choice: choice)
            } else if proposal.status.isActive,
                      let countdown = QBTCGovernanceFormat.votingCountdown(endTime: proposal.votingEndTime) {
                HStack(spacing: 4) {
                    Icon(.clock, color: Theme.colors.textTertiary, size: 12)
                    Text(countdown)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textTertiary)
                }
            }
            Spacer()
            Icon(.chevronRight, color: Theme.colors.textTertiary, size: 16)
        }
    }
}
