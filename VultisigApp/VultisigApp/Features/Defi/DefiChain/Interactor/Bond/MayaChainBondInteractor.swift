//
//  MayaChainBondInteractor.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 23/11/2025.
//

struct MayaChainBondInteractor: BondInteractor {
    func fetchBondPositions(vault: Vault) async -> (active: [BondPosition], available: [BondNode]) {
        ([], [])
    }
    
    func canUnbond() async -> Bool {
        true
    }
}
