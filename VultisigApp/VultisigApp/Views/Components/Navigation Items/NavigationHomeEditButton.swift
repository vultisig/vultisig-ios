//
//  NavigationHomeEditButton.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-04-17.
//

import SwiftUI

struct NavigationHomeEditButton: View {
    let vault: Vault?
    let showVaultsList: Bool
    @Binding var isEditingVaults: Bool
    @Binding var isEditingChains: Bool
    
    var body: some View {
        if showVaultsList {
            vaultsListEditButton
        } else {
            vaultDetailSettingButton
        }
    }
    
    var vaultsListEditButton: some View {
        Button {
            isEditingVaults.toggle()
        } label: {
            if isEditingVaults {
                doneButton
            } else {
                editButton
            }
        }
    }
    
    var vaultDetailSettingButton: some View {
        Button {
            isEditingChains.toggle()
        } label: {
            if isEditingChains {
                doneButton
            } else {
                editButton
            }
        }
    }
    
    var editButton: some View {
        NavigationEditButton()
    }
    
    var doneButton: some View {
        Text(NSLocalizedString("done", comment: ""))
            .font(.body18MenloBold)
            .foregroundColor(.neutral0)
    }
}

#Preview {
    ZStack {
        Background()
        VStack {
            NavigationHomeEditButton(vault: Vault.example, showVaultsList: true, isEditingVaults: .constant(true), isEditingChains: .constant(true))
            NavigationHomeEditButton(vault: Vault.example, showVaultsList: true, isEditingVaults: .constant(false), isEditingChains: .constant(false))
        }
    }
}
