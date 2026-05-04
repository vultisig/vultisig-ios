//
//  LPsInteractor.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/11/2025.
//

protocol LPsInteractor {
    /// Returns one DTO per pool the API successfully returned. Top-level failures return an
    /// empty array — storage upserts only what's returned, so persisted rows keep their last
    /// good value.
    func fetchLPPositions(vault: Vault) async -> [LPPositionData]
}
