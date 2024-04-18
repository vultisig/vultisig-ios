//
//  NavigationHomeEditButton.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-04-17.
//

import SwiftUI

struct NavigationHomeEditButton: View {
    let showVaultsList: Bool
    let vault: Vault?
    
    var body: some View {
        if showVaultsList {
            vaultsListEditButton
        } else {
            vaultDetailEditButton
        }
    }
    
    var vaultsListEditButton: some View {
        Button {
            
        } label: {
            editButton
        }
    }
    
    var vaultDetailEditButton: some View {
        NavigationLink {
            EditVaultView(vault: vault ?? Vault.example)
        } label: {
            editButton
        }
    }
    
    var editButton: some View {
        NavigationEditButton()
    }
}

#Preview {
    NavigationHomeEditButton(showVaultsList: true, vault: Vault.example)
}
