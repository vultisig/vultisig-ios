//
//  FolderDetailCellViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-10-08.
//

import SwiftUI

class FolderDetailCellViewModel: ObservableObject {
    @Published var order: Int = 0
    @Published var totalSigners: Int = 0
    @Published var devicesInfo: [DeviceInfo] = []
    @Published var isFastVault: Bool = false
    
    func assignSigners(_ vault: Vault) {
        devicesInfo = vault.signers.enumerated().map { index, signer in
            DeviceInfo(Index: index, Signer: signer)
        }
    }
    
    func setupLabel(_ vault: Vault) {
        totalSigners = devicesInfo.count
        checkForFastSign()
        checkForAssignedPart(vault)
    }
    
    func checkForFastSign() {
        for index in 0..<devicesInfo.count {
            if devicesInfo[index].Signer.lowercased().hasPrefix("server-") {
                isFastVault = true
                return
            }
        }
    }
    
    func checkForAssignedPart(_ vault: Vault) {
        for index in 0..<devicesInfo.count {
            if devicesInfo[index].Signer == vault.localPartyID {
                order = index+1
                return
            }
        }
    }
}
