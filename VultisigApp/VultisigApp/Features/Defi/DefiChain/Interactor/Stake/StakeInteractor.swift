//
//  StakeInteractor.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/11/2025.
//

protocol StakeInteractor {
    /// Returns one DTO per coin that was successfully fetched. Per-coin failures are silently
    /// omitted — storage upserts only what's returned, so the persisted row keeps its last good
    /// value until the next refresh.
    func fetchStakePositions(vault: Vault) async -> [StakePositionData]
}
