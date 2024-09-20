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
            GeometryReader { proxy in
                Background()
                    .onAppear {
                        setData(proxy)
                    }
            }
            
            main
        }
        .navigationTitle(NSLocalizedString("deleteVaultTitle", comment: "Delete Vault"))
    }
    
    var main: some View {
        view
    }
    
    var view: some View {
        VStack(spacing: 32) {
            logo
            details
            
            if !isPhoneSE {
                Spacer()
            }
            
            checkboxes
            button
        }
        .padding(18)
        .padding(.top, 12)
        .navigationDestination(isPresented: $navigateBackToHome) {
            HomeView(selectedVault: vaults.first, showVaultsList: true)
        }
        .alert(isPresented: $showAlert) {
            alert
        }
    }
    
    var logo: some View {
        let spacing: CGFloat = 28
                
        return VStack(spacing: spacing) {
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
        let spacing: CGFloat = isPhoneSE ? 16 : 24
                
        return VStack(spacing: spacing) {
            Checkbox(isChecked: $permanentDeletionCheck, text: "vaultWillBeDeletedPermanentlyPrompt")
            Checkbox(isChecked: $canLoseFundCheck, text: "canLoseFundsPrompt")
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
}
#endif
