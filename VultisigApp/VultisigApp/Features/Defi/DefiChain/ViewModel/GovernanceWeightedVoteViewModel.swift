//
//  GovernanceWeightedVoteViewModel.swift
//  VultisigApp
//
//  Backs `GovernanceWeightedVoteSheet`. Owns the per-option whole-percent
//  weights and the weighted-vote rules: the weights must sum to 100%, and on
//  submit the non-zero options are emitted as `CosmosGovVoteOption`s with
//  weights as fractions (e.g. 70% -> 0.7). Keeping these rules out of the view
//  follows the MVVM boundary (business logic in ViewModels, not views).
//

import Foundation

@MainActor
final class GovernanceWeightedVoteViewModel: ObservableObject {
    /// Whole-percent weight per option (0...100). Defaults to an even 25 each.
    @Published var weights: [CosmosGovVoteChoice: Int] = [
        .yes: 25, .no: 25, .noWithVeto: 25, .abstain: 25
    ]

    var total: Int {
        CosmosGovVoteChoice.allCases.reduce(0) { $0 + (weights[$1] ?? 0) }
    }

    var isValid: Bool {
        total == 100
    }

    func weight(for choice: CosmosGovVoteChoice) -> Int {
        weights[choice] ?? 0
    }

    func setWeight(_ value: Int, for choice: CosmosGovVoteChoice) {
        weights[choice] = max(0, min(100, value))
    }

    /// Non-zero options with weights as fractions (e.g. 70% -> 0.7). Order
    /// follows `CosmosGovVoteChoice.allCases` for a stable memo.
    func buildOptions() -> [CosmosGovVoteOption] {
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
