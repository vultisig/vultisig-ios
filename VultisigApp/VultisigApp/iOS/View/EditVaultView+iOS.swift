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
            .navigationTitle(NSLocalizedString("editVault", comment: "Edit Vault View title"))
            .navigationBarTitleDisplayMode(.inline)
    }
    
    var view: some View {
        ScrollView {
            VStack(spacing: 16) {
                deviceName
                vaultDetails
                backupVault
                editVault
                reshareVault
                if vault.isFastVault {
                    biometrySelectionCell
                }
                deleteVault
            }
        }
    }
}
#endif
