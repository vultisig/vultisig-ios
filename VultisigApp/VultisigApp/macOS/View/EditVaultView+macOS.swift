//
//  EditVaultView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-19.
//

#if os(macOS)
import SwiftUI

extension EditVaultView {
    var main: some View {
        VStack {
            headerMac
            view
        }
    }
    
    var headerMac: some View {
        GeneralMacHeader(title: "editVault")
    }
    
    var navigation: some View {
        base
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
            .padding(.horizontal, 25)
        }
    }
}
#endif
