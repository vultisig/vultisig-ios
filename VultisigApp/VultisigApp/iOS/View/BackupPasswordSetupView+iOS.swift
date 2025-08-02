//
//  BackupPasswordSetupView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-19.
//

#if os(iOS)
import SwiftUI

extension BackupPasswordSetupView {
    var content: some View {
        ZStack {
            Background()
            main
        }
        .navigationTitle(NSLocalizedString("backup", comment: "Backup"))
        .navigationBarTitleDisplayMode(.inline)
    }
    
    var main: some View {
        view
            .navigationDestination(isPresented: $navigationLinkActive) {
                BackupVaultSuccessView(tssType: tssType, vault: vault)
            }
            .navigationDestination(isPresented: $homeLinkActive) {
                HomeView(selectedVault: vault)
            }
    }
    
    var view: some View {
        VStack {
            passwordField
            Spacer()
            disclaimer
            buttons
        }
    }
    
    @ViewBuilder
    var saveButton: some View {
            PrimaryButton(title: "save") {
                handleProxyTap()
                if let fileURL = backupViewModel.encryptedFileURLWithPassowrd {
                    activityItems = [fileURL]
                }
            }
            .shareSheet(isPresented: $showSaveShareSheet, activityItems: activityItems) { didSave in
                if didSave {
                    fileSaved()
                    dismissView()
                }
            }
    }
    
}
#endif
