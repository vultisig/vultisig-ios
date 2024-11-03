//
//  VaultDeletionConfirmView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-19.
//

#if os(macOS)
import SwiftUI

extension VaultDeletionConfirmView {
    var content: some View {
        ZStack {
            Background()
            main
        }
    }
    
    var main: some View {
        VStack {
            headerMac
            view
            deleteButton
        }
    }
    
    var headerMac: some View {
        GeneralMacHeader(title: "deleteVaultTitle")
    }
    
    var view: some View {
        ScrollView {
            VStack(spacing: 32) {
                logo
                details
                checkboxes
            }
            .padding(25)
        }
        .navigationDestination(isPresented: $navigateBackToHome) {
            HomeView(selectedVault: vaults.first, showVaultsList: true)
        }
        .alert(isPresented: $showAlert) {
            alert
        }
    }
    
    var logo: some View {
        VStack(spacing: 28) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title80Menlo)
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.neutral0, Color.alertRed)
            
            Text(NSLocalizedString("youArePermanentlyDeletingVault", comment: ""))
                .font(.body16MenloBold)
                .foregroundColor(.neutral0)
                .frame(maxWidth: 200)
                .multilineTextAlignment(.center)
                .fixedSize()
        }
    }
    
    var checkboxes: some View {
        VStack(spacing: 12) {
            Checkbox(isChecked: $permanentDeletionCheck, text: "vaultWillBeDeletedPermanentlyPrompt")
            Checkbox(isChecked: $canLoseFundCheck, text: "canLoseFundsPrompt")
            Checkbox(isChecked: $vaultBackupCheck, text: "madeVaultBackupPrompt")
        }
        .padding(.bottom, 50)
    }
    
    var deleteButton: some View {
        Button {
            delete()
        } label: {
            FilledButton(title: "deleteVaultTitle", background: Color.alertRed)
        }
        .padding(.top, 25)
        .padding(.bottom, 40)
        .padding(.horizontal, 25)
    }
}
#endif
