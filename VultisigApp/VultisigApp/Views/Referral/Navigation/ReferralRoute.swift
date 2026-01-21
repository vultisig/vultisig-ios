//
//  ReferralRoute.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 15/12/2025.
//

import Foundation

enum ReferralRoute: Hashable {
    case initial
    case onboarding
    case main
    case vaultSelection(selectedVaultViewModel: VaultSelectedViewModel)
    case referredCodeForm
    case createReferral(selectedVaultViewModel: VaultSelectedViewModel)
    case editReferral(selectedVaultViewModel: VaultSelectedViewModel, thornameDetails: THORName?, currentBlockheight: UInt64)
}

final class VaultSelectedViewModel: ObservableObject, Hashable {
    static func == (lhs: VaultSelectedViewModel, rhs: VaultSelectedViewModel) -> Bool {
        lhs.selectedVault == rhs.selectedVault
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(selectedVault)
    }
    
    @Published var selectedVault: Vault?
    
    init(selectedVault: Vault? = nil) {
        self.selectedVault = selectedVault
    }
}
