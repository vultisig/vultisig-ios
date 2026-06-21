//
//  GovernanceProposalDetailScreen.swift
//  VultisigApp
//
//  Detail sheet for a single QBTC governance proposal: title, summary,
//  status, the wrapped message types (rendered generically by `@type`,
//  including `/qbtc.qbtc.v1.*`), the full tally breakdown, the voting
//  window, and the user's recorded-vote badge. For an active (voting-
//  period) proposal it surfaces the vote controls; the parent builds and
//  launches the keysign from the chosen option(s).
//

import SwiftUI

struct GovernanceProposalDetailScreen: View {
    let proposal: CosmosGovProposal
    let tally: CosmosGovTallyResult
    let params: CosmosGovParams?
    let myVote: CosmosGovVote?
    /// Whether the vault's native balance can cover the vote tx fee. When
    /// `false` the vote controls are disabled and a hint explains why, so a
    /// 0/dust-balance user can't start a flow that would fail at broadcast.
    var canVote: Bool = true
    /// Single-option vote chosen from the sheet. The parent builds the
    /// `QBTC_VOTE:` tx and launches verify → ML-DSA keysign. Nil disables the
    /// vote controls (read-only contexts / previews).
    var onVote: ((CosmosGovVoteChoice) -> Void)?
    /// Weighted vote (per-option weights summing to 1.0). The parent builds
    /// the `QBTC_VOTEW:` tx. Nil hides the weighted-vote entry point.
    var onWeightedVote: (([CosmosGovVoteOption]) -> Void)?

    @State private var showWeightedSheet = false

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                if !proposal.summary.isEmpty {
                    summarySection
                }
                tallySection
                votingWindowSection
                if !proposal.messageTypes.isEmpty {
                    messagesSection
                }
                if proposal.status.isActive, let onVote {
                    voteSection(onVote: onVote)
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.colors.bgPrimary)
        .presentationBackground { Theme.colors.bgPrimary.padding(.bottom, -1000) }
        .crossPlatformSheet(isPresented: $showWeightedSheet) {
            GovernanceWeightedVoteSheet(proposal: proposal) { options in
                showWeightedSheet = false
                onWeightedVote?(options)
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(String(format: "governanceProposalNumber".localized, String(proposal.id)))
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
                Spacer()
                GovernanceStatusBadge(status: proposal.status)
            }
            Text(proposal.title.isEmpty ? "governanceUntitledProposal".localized : proposal.title)
                .font(Theme.fonts.title3)
                .foregroundStyle(Theme.colors.textPrimary)
                .multilineTextAlignment(.leading)
            if let choice = myVote?.primaryChoice {
                GovernanceMyVoteBadge(choice: choice)
            }
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("governanceSummary".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textSecondary)
            Text(proposal.summary)
                .font(Theme.fonts.bodyMRegular)
                .foregroundStyle(Theme.colors.textPrimary)
                .multilineTextAlignment(.leading)
        }
    }

    private var tallySection: some View {
        card(title: "governanceTally".localized) {
            GovernanceTallyBar(tally: tally, showsLegend: true)
            if tally.total == 0 {
                Text("governanceNoVotesYet".localized)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
            }
            if let quorumText {
                Separator(color: Theme.colors.borderLight, opacity: 1)
                detailRow(label: "governanceQuorum".localized, value: quorumText)
            }
        }
    }

    /// Quorum requirement as a percentage string (e.g. "33.4%"), when the
    /// gov params loaded. `nil` hides the row.
    private var quorumText: String? {
        guard let quorum = params?.quorum else { return nil }
        let percent = NSDecimalNumber(decimal: quorum * 100).doubleValue
        return String(format: "%.1f%%", percent)
    }

    @ViewBuilder
    private var votingWindowSection: some View {
        card(title: "governanceVotingWindow".localized) {
            if let start = proposal.votingStartTime {
                detailRow(label: "governanceVotingStart".localized, value: Self.dateFormatter.string(from: start))
            }
            if let end = proposal.votingEndTime {
                detailRow(label: "governanceVotingEnd".localized, value: Self.dateFormatter.string(from: end))
                if proposal.status.isActive, let countdown = QBTCGovernanceFormat.votingCountdown(endTime: end) {
                    detailRow(label: "governanceTimeRemaining".localized, value: countdown)
                }
            }
        }
    }

    private var messagesSection: some View {
        card(title: "governanceMessages".localized) {
            ForEach(Array(proposal.messageTypes.enumerated()), id: \.offset) { _, type in
                HStack(spacing: 8) {
                    Text(QBTCGovernanceFormat.messageShortLabel(type))
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textPrimary)
                    Spacer(minLength: 8)
                    Text(type)
                        .font(Theme.fonts.caption10)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    /// Vote controls for an active proposal. Re-voting is allowed while the
    /// voting period is open (Cosmos lets a voter change their vote), so the
    /// header switches to "Change your vote" once a recorded vote exists.
    private func voteSection(onVote: @escaping (CosmosGovVoteChoice) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(myVote == nil ? "governanceCastVote".localized : "governanceChangeVote".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textSecondary)
            // Dim only the interactive controls when voting is disabled so the
            // insufficient-balance warning below stays at full opacity.
            VStack(alignment: .leading, spacing: 12) {
                ForEach(CosmosGovVoteChoice.allCases) { choice in
                    PrimaryButton(
                        title: choice.displayTitle,
                        type: choice == .yes ? .primary : .secondary
                    ) {
                        onVote(choice)
                    }
                    .disabled(!canVote)
                }
                if onWeightedVote != nil {
                    Button {
                        showWeightedSheet = true
                    } label: {
                        Text("governanceVoteWithWeights".localized)
                            .font(Theme.fonts.bodySMedium)
                            .foregroundStyle(Theme.colors.primaryAccent4)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canVote)
                }
            }
            .opacity(canVote ? 1 : 0.5)
            if !canVote {
                Text("governanceInsufficientBalanceForFee".localized)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.alertWarning)
                    .multilineTextAlignment(.leading)
            }
        }
    }

    // MARK: - Reusable building blocks

    @ViewBuilder
    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textSecondary)
            content()
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

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textTertiary)
            Spacer()
            Text(value)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)
        }
    }
}
