//
//  VaultCellViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-19.
//

import SwiftUI

class VaultCellViewModel: ObservableObject {
    @Published var order: Int = 0
    @Published var totalSigners: Int = 0
    @Published var isFastVault: Bool = false
    @Published var devicesInfo: [DeviceInfo] = []
    
    func setupCell(_ vault: Vault) {
        assignSigners(vault)
        setupLabel(vault)
    }
    
    private func assignSigners(_ vault: Vault) {
        devicesInfo = vault.signers.enumerated().map { index, signer in
            DeviceInfo(Index: index, Signer: signer)
        }
    }
    
    private func setupLabel(_ vault: Vault) {
        totalSigners = devicesInfo.count
        checkForFastSign()
        checkForAssignedPart(vault)
    }
    
    private func checkForFastSign() {
        for index in 0..<devicesInfo.count {
            if devicesInfo[index].Signer.lowercased().hasPrefix("server-") {
                isFastVault = true
                return
            }
        }
    }
    
    private func checkForAssignedPart(_ vault: Vault) {
        for index in 0..<devicesInfo.count {
            if devicesInfo[index].Signer == vault.localPartyID {
                order = index+1
                return
            }
        }
    }
}
