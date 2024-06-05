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
    
    @State var permanentDeletionCheck = false
    @State var canLooseFundCheck = false
    @State var vaultBackupCheck = false
    @State var navigateBackToHome = false
    
    @Environment(\.modelContext) private var modelContext
    
    @Query var vaults: [Vault]
    
    var body: some View {
        ZStack {
            Background()
            view
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString("deleteVaultTitle", comment: "Delete Vault"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationBackButton()
            }
        }
    }
    
    var view: some View {
        VStack(spacing: 48) {
            Spacer()
            logo
            Spacer()
            checkboxes
            button
        }
        .padding(18)
        .navigationDestination(isPresented: $navigateBackToHome) {
            HomeView(selectedVault: vaults.first, showVaultsList: true)
        }
    }
    
    var logo: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title80Menlo)
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.neutral0, Color.alertRed)
            
            Text(NSLocalizedString("youArePermanentlyDeletingVault", comment: ""))
                .font(.body16MenloBold)
                .foregroundColor(.neutral0)
                .frame(maxWidth: 200)
                .multilineTextAlignment(.center)
        }
    }
    
    var checkboxes: some View {
        VStack(spacing: 32) {
            Checkbox(isChecked: $permanentDeletionCheck, text: "vaultWillBeDeletedPermanentlyPrompt")
            Checkbox(isChecked: $canLooseFundCheck, text: "canLooseFundsPrompt")
            Checkbox(isChecked: $vaultBackupCheck, text: "madeVaultBackupPrompt")
        }
    }
    
    var button: some View {
        Button {
            delete()
        } label: {
            FilledButton(title: "deleteVaultTitle", background: Color.alertRed)
        }
    }
    
    private func delete() {
        modelContext.delete(vault)
        do {
            try modelContext.save()
        } catch {
            print("Error: \(error)")
        }
        ApplicationState.shared.currentVault = nil
        navigateBackToHome = true
    }
}

#Preview {
    VaultDeletionConfirmView(vault: Vault.example)
}
