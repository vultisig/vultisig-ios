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

    private let logic = VaultCellLogic()

    func setupCell(_ vault: Vault) {
        let result = logic.setupCell(vault)
        devicesInfo = result.devicesInfo
        totalSigners = result.totalSigners
        isFastVault = result.isFastVault
        order = result.order
    }
}

// MARK: - VaultCellLogic

struct VaultCellLogic {

    struct SetupResult {
        let devicesInfo: [DeviceInfo]
        let totalSigners: Int
        let isFastVault: Bool
        let order: Int
    }

    func setupCell(_ vault: Vault) -> SetupResult {
        let devicesInfo = assignSigners(vault)
        let totalSigners = devicesInfo.count
        let isFastVault = checkForFastSign(localPartyID: vault.localPartyID, devicesInfo: devicesInfo)
        let order = checkForAssignedPart(vault, devicesInfo: devicesInfo)

        return SetupResult(
            devicesInfo: devicesInfo,
            totalSigners: totalSigners,
            isFastVault: isFastVault,
            order: order
        )
    }

    private func assignSigners(_ vault: Vault) -> [DeviceInfo] {
        return vault.signers.enumerated().map { index, signer in
            DeviceInfo(Index: index, Signer: signer)
        }
    }

    private func checkForFastSign(localPartyID: String, devicesInfo: [DeviceInfo]) -> Bool {
        if localPartyID.lowercased().hasPrefix("server-") {
            return false
        } else {
            for index in 0..<devicesInfo.count {
                if devicesInfo[index].Signer.lowercased().hasPrefix("server-") {
                    return true
                }
            }
            return false
        }
    }

    private func checkForAssignedPart(_ vault: Vault, devicesInfo: [DeviceInfo]) -> Int {
        for index in 0..<devicesInfo.count {
            if devicesInfo[index].Signer == vault.localPartyID {
                return index+1
            }
        }
        return 0
    }
}
