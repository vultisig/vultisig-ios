//
//  DefiTHORChainBondViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/10/2025.
//

import Foundation

final class DefiTHORChainBondViewModel: ObservableObject {
    @Published private(set) var vault: Vault
    
    private let thorchainAPIService = THORChainAPIService()
    
    init(vault: Vault) {
        self.vault = vault
    }
    
    func update(vault: Vault) {
        self.vault = vault
    }
    
    func refresh() async {
        guard let runeCoin = vault.coins.first(where: { $0.isRune }) else {
            return
        }
        
        await BalanceService.shared.updateBalance(for: runeCoin)
        
        let nodes = try? await thorchainAPIService.getNodes()
    }
}
