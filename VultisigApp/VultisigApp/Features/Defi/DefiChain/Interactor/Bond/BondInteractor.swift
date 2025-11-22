//
//  BondInteractor.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/11/2025.
//

protocol BondInteractor {
    func fetchBondPositions(vault: Vault) async -> (active: [BondPosition], available: [BondNode])
    func canUnbond() async -> Bool
}
