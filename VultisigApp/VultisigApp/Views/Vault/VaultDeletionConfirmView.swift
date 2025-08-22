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
            HomeView(selectedVault: vaults.first, showVaultsList: true)
        }
        .alert(isPresented: $showAlert) {
            alert
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
    
    var backgroundView: some View {
        Ellipse()
            .fill(Color(hex: "D32829"))
            .aspectRatio(contentMode: .fit)
            .opacity(0.2)
            .blur(radius: 120)
    }
}

#Preview {
    VaultDeletionConfirmView(vault: Vault.example, devicesInfo: [], vaults: [])
        .environmentObject(HomeViewModel())
}
