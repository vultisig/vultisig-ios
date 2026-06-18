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

    @StateObject private var viewModel = GovernanceWeightedVoteViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            optionRows
            totalRow
            PrimaryButton(title: "governanceSubmitWeightedVote".localized) {
                onSubmit(viewModel.buildOptions())
            }
            .disabled(!viewModel.isValid)
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
                    get: { viewModel.weight(for: choice) },
                    set: { viewModel.setWeight($0, for: choice) }
                ),
                in: 0...100,
                step: 5
            ) {
                Text("\(viewModel.weight(for: choice))%")
                    .font(Theme.fonts.bodyMMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .monospacedDigit()
            }
            .labelsHidden()
            Text("\(viewModel.weight(for: choice))%")
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
            Text("\(viewModel.total)%")
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(viewModel.isValid ? Theme.colors.alertSuccess : Theme.colors.alertError)
                .monospacedDigit()
        }
    }
}
