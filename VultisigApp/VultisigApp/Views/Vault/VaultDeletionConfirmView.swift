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

    @State var nextSelectedVault: Vault? = nil
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.router) var router
    @EnvironmentObject var homeViewModel: HomeViewModel
    @EnvironmentObject var appViewModel: AppViewModel

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
                .foregroundColor(Theme.colors.textTertiary)
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
        // fetch the vault before deleting it , so we can make sure we have all the relationships loaded
        let publicKeyECDSA = vault.pubKeyECDSA
        let fetchNextVaultRequest = FetchDescriptor<Vault>(predicate: #Predicate { $0.pubKeyECDSA != publicKeyECDSA })
        let vaultsNext = try? modelContext.fetch(fetchNextVaultRequest)
        nextSelectedVault = vaultsNext?.first
        
        if nextSelectedVault != nil {
            appViewModel.set(selectedVault: nextSelectedVault, showingVaultSelector: false)
        } else {
            router.navigate(to: VaultRoute.createVault(showBackButton: false))
        }
        
        // Add delay on deletion to prevent accesing deleted vault during navigation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            do {
                let fetchRequest = FetchDescriptor<Vault>(predicate: #Predicate { $0.pubKeyECDSA == publicKeyECDSA })
                let vaultsToDelete = try modelContext.fetch(fetchRequest)
                if let targetToBeDeleted = vaultsToDelete.first {
                    // the following few lines are used to ensure that all relationships are loaded before deletion
                    _ = targetToBeDeleted.signers
                    _ = targetToBeDeleted.keyshares
                    _ = targetToBeDeleted.libType
                    _ = targetToBeDeleted.closedBanners
                    _ = targetToBeDeleted.defiChains
                    _ = targetToBeDeleted.defiPositions
                    _ = targetToBeDeleted.bondPositions
                    _ = targetToBeDeleted.stakePositions
                    _ = targetToBeDeleted.lpPositions
                    
                    modelContext.delete(targetToBeDeleted)
                }
                try modelContext.save()
            } catch {
                print("Error: \(error)")
            }
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
        .environmentObject(AppViewModel())
}
