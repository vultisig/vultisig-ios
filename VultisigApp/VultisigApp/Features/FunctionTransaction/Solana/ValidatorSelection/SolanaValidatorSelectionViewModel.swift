//
//  SolanaValidatorSelectionViewModel.swift
//  VultisigApp
//
//  Backs the Solana validator-picker sheet. Loads the vote-account set from
//  `SolanaStakingService`, enriches it with off-chain metadata via the
//  swappable `ValidatorMetadataProvider` seam, filters delinquent validators
//  out, sorts by activated stake descending, and surfaces search + selection
//  state. Mirrors the Cosmos `ValidatorSelectionViewModel`.
//

import Foundation
import OSLog

@MainActor
final class SolanaValidatorSelectionViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published private(set) var validators: [SolanaValidator] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: String?

    private let service: SolanaStakingServiceProtocol
    private let metadataProvider: ValidatorMetadataProvider
    private let logger = Logger(
        subsystem: "com.vultisig.app",
        category: "solana-validator-selection"
    )

    init(
        service: SolanaStakingServiceProtocol = SolanaStakingService.shared,
        metadataProvider: ValidatorMetadataProvider = StakewizValidatorMetadataProvider.shared
    ) {
        self.service = service
        self.metadataProvider = metadataProvider
    }

    var filteredValidators: [SolanaValidator] {
        guard searchText.isNotEmpty else { return validators }
        let needle = searchText.lowercased()
        return validators.filter { validator in
            validator.displayName.lowercased().contains(needle)
                || validator.votePubkey.lowercased().contains(needle)
        }
    }

    func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let raw = try await service.fetchValidators()
            let sorted = Self.sortAndFilter(raw)
            // Enrichment never throws (provider contract) — degrade to the
            // on-chain rows when metadata is unavailable.
            let metadata = await metadataProvider.metadata(forVotePubkeys: sorted.map(\.votePubkey))
            validators = sorted.map { validator in
                guard let enrichment = metadata[validator.votePubkey] else { return validator }
                var enriched = validator
                enriched.metadata = enrichment
                return enriched
            }
        } catch {
            logger.error("Validator fetch failed: \(error.localizedDescription, privacy: .public)")
            self.error = error.localizedDescription
        }
    }

    /// Keeps non-delinquent validators that voted in the current epoch, sorted
    /// by descending activated stake. Static so tests can pin the contract
    /// independent of the network layer.
    static func sortAndFilter(_ raw: [SolanaValidator]) -> [SolanaValidator] {
        raw
            .filter { !$0.isDelinquent && $0.epochVoteAccount }
            .sorted { $0.activatedStake > $1.activatedStake }
    }
}
