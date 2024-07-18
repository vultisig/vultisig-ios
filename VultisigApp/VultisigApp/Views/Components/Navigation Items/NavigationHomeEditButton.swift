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
    
    var tint: Color = Color.neutral0
    
    @EnvironmentObject var viewModel: VaultDetailViewModel
    
    var body: some View {
        if showVaultsList {
            vaultsListEditButton
        } else {
            vaultDetailQRCodeButton
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
    
    var vaultDetailQRCodeButton: some View {
        NavigationLink {
            VaultDetailQRCodeView()
        } label: {
            NavigationQRCodeButton()
        }
    }
    
    var editButton: some View {
        NavigationEditButton()
    }
    
    var doneButton: some View {
        Text(NSLocalizedString("done", comment: ""))
            .foregroundColor(tint)
#if os(iOS)
            .font(.body18MenloBold)
#elseif os(macOS)
            .font(.body18Menlo)
#endif
    }
}

#Preview {
    ZStack {
        Background()
        VStack {
            NavigationHomeEditButton(vault: Vault.example, showVaultsList: true, isEditingVaults: .constant(true))
            NavigationHomeEditButton(vault: Vault.example, showVaultsList: true, isEditingVaults: .constant(false))
        }
        .environmentObject(VaultDetailViewModel())
        .environmentObject(CoinSelectionViewModel())
    }
}
