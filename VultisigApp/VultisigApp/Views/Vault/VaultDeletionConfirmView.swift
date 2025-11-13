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
    
    @State var navigateBackToHome = false
    @State var navigateToCreateVault = false
    @State var nextSelectedVault: Vault? = nil
    
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var homeViewModel: HomeViewModel
    
    var buttonEnabled: Bool {
        permanentDeletionCheck && canLoseFundCheck && vaultBackupCheck
    }
    
    var body: some View {
        Screen(title: "deleteVaultTitle".localized) {
            VStack {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        header
                        details
                        checkboxes
                    }
                }
                deleteButton
            }
            .background(backgroundView)
        }
        .navigationDestination(isPresented: $navigateToCreateVault) {
            CreateVaultView(selectedVault: nil, showBackButton: false)
        }
        .navigationDestination(isPresented: $navigateBackToHome) {
            HomeScreen(initialVault: nextSelectedVault, showingVaultSelector: false)
        }
    }
    
    var header: some View {
        VStack(spacing: 8) {
            Icon(
                named: "triangle-alert",
                color: Theme.colors.alertError,
                size: 22
            ).padding(.bottom, 6)
            
            Text("deleteVaultTitle".localized)
                .font(Theme.fonts.title2)
                .foregroundStyle(Theme.colors.alertError)
        
            Text("youArePermanentlyDeletingVault".localized)
                .font(Theme.fonts.footnote)
                .foregroundColor(Theme.colors.textExtraLight)
        }
    }
    
    var checkboxes: some View {
        VStack(spacing: 16) {
            Checkbox(isChecked: $permanentDeletionCheck, text: "vaultWillBeDeletedPermanentlyPrompt")
            Checkbox(isChecked: $canLoseFundCheck, text: "canLoseFundsPrompt")
            Checkbox(isChecked: $vaultBackupCheck, text: "madeVaultBackupPrompt")
        }
        .padding(.bottom, 50)
    }
    
    var deleteButton: some View {
        PrimaryButton(title: "deleteVaultTitle", type: .alert) {
            delete()
        }
        .disabled(!buttonEnabled)
    }
    
    var details: some View {
        VaultDeletionDetails(vault: vault, devicesInfo: devicesInfo)
    }
    
    func delete() {
        do {
            // fetch the vault before deleting it , so we can make sure we have all the relationships loaded
            let publicKeyECDSA = vault.pubKeyECDSA
            let fetchRequest = FetchDescriptor<Vault>(predicate: #Predicate { $0.pubKeyECDSA == publicKeyECDSA })
            let vaultsToDelete = try modelContext.fetch(fetchRequest)
            if let targetToBeDeleted = vaultsToDelete.first {
                // the following few lines are used to ensure that all relationships are loaded before deletion
                _ = targetToBeDeleted.signers
                _ = targetToBeDeleted.keyshares
                _ = targetToBeDeleted.libType
                _ = targetToBeDeleted.closedBanners
                modelContext.delete(targetToBeDeleted)
            }
            try modelContext.save()
            let fetchNextVaultRequest = FetchDescriptor<Vault>(predicate: #Predicate { $0.pubKeyECDSA != publicKeyECDSA })
            let vaultsNext = try modelContext.fetch(fetchNextVaultRequest)
            nextSelectedVault = vaultsNext.first
        } catch {
            print("Error: \(error)")
        }
        
        if let nextSelectedVault {
            navigateBackToHome = true
        } else {
            navigateToCreateVault = true
        }
    }
    
    var backgroundView: some View {
        Ellipse()
            .fill(Color(hex: "D32829"))
            .aspectRatio(contentMode: .fit)
            .opacity(0.2)
            .blur(radius: 120)
    }
}

#Preview {
    VaultDeletionConfirmView(vault: Vault.example, devicesInfo: [])
        .environmentObject(HomeViewModel())
}
