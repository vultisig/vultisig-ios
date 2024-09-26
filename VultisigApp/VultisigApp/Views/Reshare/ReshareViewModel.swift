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

    private let fastVaultService = FastVaultService.shared

    @MainActor func load(vault: Vault) async {
        isLoading = true
        isFastVault = await fastVaultService.exist(pubKeyECDSA: vault.pubKeyECDSA)
        isLoading = false
    }
}
