//
//  VaultDeletionConfirmView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-05.
//

import SwiftUI

struct VaultDeletionConfirmView: View {
    @State var permanentDeletionCheck = false
    @State var canLooseFundCheck = false
    @State var vaultBackupCheck = false
    
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
        FilledButton(title: "deleteVaultTitle", background: Color.alertRed)
    }
}

#Preview {
    VaultDeletionConfirmView()
}
