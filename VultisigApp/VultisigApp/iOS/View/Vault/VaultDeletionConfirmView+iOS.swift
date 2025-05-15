//
//  VaultDeletionConfirmView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-19.
//

#if os(iOS)
import SwiftUI

extension VaultDeletionConfirmView {
    private var idiom : UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
    
    var content: some View {
        ZStack {
            Background()
            main
        }
        .navigationTitle(NSLocalizedString("deleteVaultTitle", comment: "Delete Vault"))
        .navigationBarTitleDisplayMode(.inline)
    }
    
    var main: some View {
        VStack {
            view
            deleteButton
        }
    }
    
    var view: some View {
        list
            .navigationDestination(isPresented: $navigateBackToHome) {
                HomeView(selectedVault: vaults.first, showVaultsList: true)
            }
            .alert(isPresented: $showAlert) {
                alert
            }
    }
    
    var list: some View {
        ScrollView {
            VStack(spacing: 32) {
                logo
                details
                checkboxes
            }
            .padding(18)
            .padding(.top, 12)
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
        VStack(spacing: 24) {
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
            FilledButton(
                title: "deleteVaultTitle",
                textColor: allFieldsChecked() ? .backgroundBlue : .disabledText,
                background: allFieldsChecked() ? Color.alertRed : .disabledButtonBackground
            )
            .padding(18)
        }
    }
}
#endif
