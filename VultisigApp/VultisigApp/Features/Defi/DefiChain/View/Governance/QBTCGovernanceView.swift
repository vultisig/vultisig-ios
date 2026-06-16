//
//  QBTCGovernanceView.swift
//  VultisigApp
//
//  QBTC governance segment of the DeFi chain tab. Lists active (voting-
//  period) and past proposals as cards, with a status badge, voting-end
//  countdown, compact tally bar, and the user's recorded-vote badge.
//  Tapping a card opens the detail sheet. Handles the empty / all-historical
//  state (qbtc-testnet currently has a single PASSED proposal).
//

import SwiftUI

struct QBTCGovernanceView: View {
    @ObservedObject var viewModel: QBTCGovernanceViewModel
    /// Builds + launches the single-option vote flow for a chosen proposal +
    /// option. The parent assembles the `QBTC_VOTE:` tx and navigates to
    /// verify → ML-DSA keysign.
    var onVote: (CosmosGovProposal, CosmosGovVoteChoice) -> Void
    /// Builds + launches the weighted-vote flow (`QBTC_VOTEW:` tx).
    var onWeightedVote: (CosmosGovProposal, [CosmosGovVoteOption]) -> Void

    @State private var selectedProposal: CosmosGovProposal?

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.activeProposals.isEmpty && viewModel.pastProposals.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 32)
            } else if viewModel.loadFailed && viewModel.isEmpty {
                errorState
            } else if viewModel.isEmpty {
                emptyState
            } else {
                populatedState
            }
        }
        .crossPlatformSheet(item: $selectedProposal) { proposal in
            GovernanceProposalDetailScreen(
                proposal: proposal,
                tally: viewModel.tally(for: proposal),
                params: viewModel.params,
                myVote: viewModel.myVote(for: proposal),
                onVote: { choice in
                    selectedProposal = nil
                    onVote(proposal, choice)
                },
                onWeightedVote: { options in
                    selectedProposal = nil
                    onWeightedVote(proposal, options)
                }
            )
        }
    }

    @ViewBuilder
    private var populatedState: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !viewModel.activeProposals.isEmpty {
                section(
                    title: "governanceActiveProposals".localized,
                    proposals: viewModel.activeProposals
                )
            }
            if !viewModel.pastProposals.isEmpty {
                section(
                    title: "governancePastProposals".localized,
                    proposals: viewModel.pastProposals
                )
            }
        }
    }

    @ViewBuilder
    private func section(title: String, proposals: [CosmosGovProposal]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textSecondary)
            ForEach(proposals) { proposal in
                GovernanceProposalRow(
                    proposal: proposal,
                    tally: viewModel.tally(for: proposal),
                    myVote: viewModel.myVote(for: proposal),
                    onTap: { selectedProposal = proposal }
                )
            }
        }
    }

    private var emptyState: some View {
        governanceMessage(
            title: "governanceEmptyTitle".localized,
            subtitle: "governanceEmptySubtitle".localized
        )
    }

    private var errorState: some View {
        governanceMessage(
            title: "governanceErrorTitle".localized,
            subtitle: "governanceErrorSubtitle".localized
        )
    }

    private func governanceMessage(title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.textPrimary)
            Text(subtitle)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.colors.bgSurface1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.colors.border, lineWidth: 1)
        )
    }
}
