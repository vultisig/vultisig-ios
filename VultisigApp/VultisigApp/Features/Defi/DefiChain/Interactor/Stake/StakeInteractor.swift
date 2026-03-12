//
//  StakeInteractor.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/11/2025.
//

protocol StakeInteractor {
    @MainActor
    func fetchStakePositions(vault: Vault) async -> [StakePosition]
}
