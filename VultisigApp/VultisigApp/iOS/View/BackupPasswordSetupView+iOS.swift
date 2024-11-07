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
                HomeView(selectedVault: vault, showVaultsList: false, shouldJoinKeygen: false)
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
    
    var saveButton: some View {
        Button(action: {
            handleProxyTap()
        }) {
            FilledButton(title: "save")
        }
        .sheet(isPresented: $showSaveShareSheet, onDismiss: {
            dismissView()
        }) {
            if let fileURL = backupViewModel.encryptedFileURLWithPassowrd {
                ShareSheetViewController(activityItems: [fileURL])
                    .presentationDetents([.medium])
                    .ignoresSafeArea(.all)
            }
        }
    }
    
    var skipButton: some View {
        Button(action: {
            showSkipShareSheet = true
            fileSaved()
        }) {
            OutlineButton(title: "skip")
        }
        .sheet(isPresented: $showSkipShareSheet, onDismiss: {
            dismissView()
        }) {
            if let fileURL = backupViewModel.encryptedFileURLWithoutPassowrd {
                ShareSheetViewController(activityItems: [fileURL])
                    .presentationDetents([.medium])
                    .ignoresSafeArea(.all)
            }
        }
    }
}
#endif
