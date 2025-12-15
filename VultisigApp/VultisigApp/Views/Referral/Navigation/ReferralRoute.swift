//
//  ReferralRoute.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 15/12/2025.
//

enum ReferralRoute: Hashable {
    case referredCodeForm(referredViewModel: ReferredViewModel, referralViewModel: ReferralViewModel)
    case vaultSelection(selectedVault: Vault?)
}
