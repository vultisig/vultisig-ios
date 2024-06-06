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
    
    @EnvironmentObject var viewModel: VaultDetailViewModel
    
    var body: some View {
        if showVaultsList {
            vaultsListEditButton
        } else {
            vaultDetailRefreshButton
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
    
    var vaultDetailRefreshButton: some View {
        NavigationRefreshButton {
            viewModel.updateBalance()
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
            NavigationHomeEditButton(vault: Vault.example, showVaultsList: true, isEditingVaults: .constant(true))
            NavigationHomeEditButton(vault: Vault.example, showVaultsList: true, isEditingVaults: .constant(false))
        }
        .environmentObject(VaultDetailViewModel())
        .environmentObject(CoinSelectionViewModel())
    }
}
