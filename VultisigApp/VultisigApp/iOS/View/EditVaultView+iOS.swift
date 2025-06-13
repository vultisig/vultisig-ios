//
//  EditVaultView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-19.
//

#if os(iOS)
import SwiftUI

extension EditVaultView {
    var main: some View {
        view
    }
    
    var navigation: some View {
        base
            .navigationTitle(NSLocalizedString("vaultSettings", comment: "Edit Vault View title"))
            .navigationBarTitleDisplayMode(.inline)
    }
    
    var view: some View {
        ScrollView {
            VStack(spacing: 16) {
                deviceName
                vaultDetails
                backupVault
                editVault
                
                if vault.libType == nil || vault.libType == .GG20 {
                    migrateVault
                }
                
                // ONLY DKLS VAULTS CAN BE RESHARED
                if vault.libType != nil && vault.libType == .DKLS {
                    reshareVault
                }
                
                if vault.isFastVault {
                    biometrySelectionCell
                }
                
                customMessage
                deleteVault
            }
        }
    }
}
#endif
