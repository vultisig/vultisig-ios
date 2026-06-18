//
//  GovernanceWeightedVoteSheet.swift
//  VultisigApp
//
//  Weighted-vote entry sheet: a percentage stepper per option (Yes / No /
//  NoWithVeto / Abstain) that must sum to 100%. On submit it emits the
//  non-zero options as `CosmosGovVoteOption`s (weights as fractions summing
//  to 1.0) for the parent to build a `QBTC_VOTEW:` tx. Options with 0%
//  weight are dropped (the chain rejects a zero-weight option).
//

import SwiftUI

struct GovernanceWeightedVoteSheet: View {
    let proposal: CosmosGovProposal
    var onSubmit: ([CosmosGovVoteOption]) -> Void

    /// Whole-percent weight per option (0...100). Defaults to an even 25 each.
    @State private var weights: [CosmosGovVoteChoice: Int] = [
        .yes: 25, .no: 25, .noWithVeto: 25, .abstain: 25
    ]

    private var total: Int {
        CosmosGovVoteChoice.allCases.reduce(0) { $0 + (weights[$1] ?? 0) }
    }

    private var isValid: Bool {
        total == 100
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            optionRows
            totalRow
            PrimaryButton(title: "governanceSubmitWeightedVote".localized) {
                onSubmit(buildOptions())
            }
            .disabled(!isValid)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.colors.bgPrimary)
        .presentationBackground { Theme.colors.bgPrimary.padding(.bottom, -1000) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("governanceWeightedVoteTitle".localized)
                .font(Theme.fonts.title3)
                .foregroundStyle(Theme.colors.textPrimary)
            Text(String(format: "governanceProposalNumber".localized, String(proposal.id)))
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
        }
    }

    private var optionRows: some View {
        VStack(spacing: 12) {
            ForEach(CosmosGovVoteChoice.allCases) { choice in
                weightRow(for: choice)
            }
        }
    }

    private func weightRow(for choice: CosmosGovVoteChoice) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(choice.tallyColor)
                .frame(width: 8, height: 8)
            Text(choice.displayTitle)
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.textPrimary)
            Spacer()
            Stepper(
                value: Binding(
                    get: { weights[choice] ?? 0 },
                    set: { weights[choice] = max(0, min(100, $0)) }
                ),
                in: 0...100,
                step: 5
            ) {
                Text("\(weights[choice] ?? 0)%")
                    .font(Theme.fonts.bodyMMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .monospacedDigit()
            }
            .labelsHidden()
            Text("\(weights[choice] ?? 0)%")
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.textPrimary)
                .monospacedDigit()
                .frame(width: 48, alignment: .trailing)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.colors.bgSurface1)
        )
    }

    private var totalRow: some View {
        HStack {
            Text("governanceWeightedTotal".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textSecondary)
            Spacer()
            Text("\(total)%")
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(isValid ? Theme.colors.alertSuccess : Theme.colors.alertError)
                .monospacedDigit()
        }
    }

    /// Non-zero options with weights as fractions (e.g. 70% -> 0.7). Order
    /// follows `CosmosGovVoteChoice.allCases` for a stable memo.
    private func buildOptions() -> [CosmosGovVoteOption] {
        CosmosGovVoteChoice.allCases.compactMap { choice in
            let percent = weights[choice] ?? 0
            guard percent > 0 else { return nil }
            return CosmosGovVoteOption(
                option: choice,
                weight: Decimal(percent) / 100
            )
        }
    }
}
