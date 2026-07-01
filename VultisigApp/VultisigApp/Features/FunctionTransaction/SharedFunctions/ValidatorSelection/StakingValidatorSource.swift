//
//  StakingValidatorSource.swift
//  VultisigApp
//
//  Per-chain data seam for the shared validator picker. Encapsulates how each
//  chain loads + sorts/filters its bonded validator set (and, for Solana,
//  enriches it with off-chain metadata) plus how a load failure maps to a
//  user-facing message — so the generic picker view-model stays chain-agnostic.
//

import Foundation

/// Loads the displayable validator set for one chain and maps load failures to a
/// user-facing message.
struct StakingValidatorSource<V: StakingValidatorConvertible> {
    let load: () async throws -> [V]
    let userFacingError: (Error) -> String
}

extension StakingValidatorSource where V == CosmosValidator {
    /// Cosmos source — bonded/un-jailed set sorted by voting power, minus any
    /// excluded validators (the redelegate source, which you can't redelegate
    /// to). Surfaces the raw error string, matching the Cosmos picker.
    static func cosmos(
        chain: Chain,
        excludedValidators: Set<String> = [],
        service: CosmosStakingServiceProtocol = CosmosStakingService()
    ) -> StakingValidatorSource<CosmosValidator> {
        StakingValidatorSource(
            load: {
                let raw = try await service.fetchValidators(chain: chain)
                return CosmosValidator.sortAndFilter(raw)
                    .filter { !excludedValidators.contains($0.operatorAddress) }
            },
            userFacingError: { $0.localizedDescription }
        )
    }
}

extension StakingValidatorSource where V == SolanaValidator {
    /// Solana source — the vote-account set sorted by activated stake, enriched
    /// with Stakewiz metadata (name/logo). Enrichment never throws (provider
    /// contract); a load failure surfaces a stable localized message.
    static func solana(
        service: SolanaStakingServiceProtocol = SolanaStakingService.shared,
        metadataProvider: ValidatorMetadataProvider = StakewizValidatorMetadataProvider.shared
    ) -> StakingValidatorSource<SolanaValidator> {
        StakingValidatorSource(
            load: {
                let raw = try await service.fetchValidators()
                let sorted = SolanaValidator.sortAndFilter(raw)
                let metadata = await metadataProvider.metadata(forVotePubkeys: sorted.map(\.votePubkey))
                return sorted.map { validator in
                    guard let enrichment = metadata[validator.votePubkey] else { return validator }
                    var enriched = validator
                    enriched.metadata = enrichment
                    return enriched
                }
            },
            userFacingError: { _ in "solanaValidatorLoadFailed".localized }
        )
    }
}
