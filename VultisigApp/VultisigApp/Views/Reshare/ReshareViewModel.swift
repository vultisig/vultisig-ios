//
//  ReshareViewModel.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 26.09.2024.
//

import Foundation

final class ReshareViewModel: ObservableObject {

    @Published var isFastVault = false
    @Published var isLoading = false
    @Published var fastVaultPassword: String = .empty

    private let fastVaultService = FastVaultService.shared

    @MainActor func load(vault: Vault) async {
        isLoading = true
        isFastVault = await fastVaultService.isEligibleForFastSign(vault: vault)
        isLoading = false
    }
}
