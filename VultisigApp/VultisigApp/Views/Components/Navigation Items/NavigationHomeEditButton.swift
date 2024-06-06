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
    @EnvironmentObject var tokenSelectionViewModel: CoinSelectionViewModel
    
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
            setData()
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
    
    private func setData() {
        guard let vault else {
            return
        }
        
        viewModel.fetchCoins(for: vault)
        viewModel.setOrder()
        viewModel.updateBalance()
        viewModel.getGroupAsync(tokenSelectionViewModel)
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
