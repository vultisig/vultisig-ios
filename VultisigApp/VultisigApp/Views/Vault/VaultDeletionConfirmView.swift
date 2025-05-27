//
//  VaultDeletionConfirmView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-05.
//

import SwiftUI
import SwiftData

struct VaultDeletionConfirmView: View {
    let vault: Vault
    let devicesInfo: [DeviceInfo]
    
    @State var permanentDeletionCheck = false
    @State var canLoseFundCheck = false
    @State var vaultBackupCheck = false
    
    @State var showAlert = false
    @State var navigateBackToHome = false
    @State var navigateToCreateVault = false
    
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var homeViewModel: HomeViewModel
    
    let vaults: [Vault]
    
    var body: some View {
        content
            .navigationDestination(isPresented: $navigateToCreateVault) {
                CreateVaultView(selectedVault: nil, showBackButton: false)
            }
    }
    
    var details: some View {
        VaultDeletionDetails(vault: vault, devicesInfo: devicesInfo)
    }
    
    func delete() {
        let vaultCount = vaults.count
        
        guard allFieldsChecked() else {
            showAlert = true
            return
        }
        homeViewModel.selectedVault = nil
        modelContext.delete(vault)
        do {
            try modelContext.save()
        } catch {
            print("Error: \(error)")
        }
        ApplicationState.shared.currentVault = nil
        
        if vaultCount > 1 {
            navigateBackToHome = true
        } else {
            navigateToCreateVault = true
        }
    }
    
    func allFieldsChecked() -> Bool {
        permanentDeletionCheck && canLoseFundCheck && vaultBackupCheck
    }
    
    var alert: Alert {
        Alert(
            title: Text(NSLocalizedString("reviewConditions", comment: "")),
            message: Text(NSLocalizedString("reviewConditionsMessage", comment: "")),
            dismissButton: .default(Text(NSLocalizedString("ok", comment: "")))
        )
    }
}

#Preview {
    VaultDeletionConfirmView(vault: Vault.example, devicesInfo: [], vaults: [])
        .environmentObject(HomeViewModel())
}
