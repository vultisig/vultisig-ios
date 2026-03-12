//
//  LPsInteractor.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/11/2025.
//

protocol LPsInteractor {
    @MainActor
    func fetchLPPositions(vault: Vault) async -> [LPPosition]
}
