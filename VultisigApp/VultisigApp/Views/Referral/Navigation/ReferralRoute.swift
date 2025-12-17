//
//  ReferralRoute.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 15/12/2025.
//

enum ReferralRoute: Hashable {
    case referredCodeForm
    case vaultSelection(selectedVault: Vault?)
    case transactionFlow(isEdit: Bool)
    case main
}
