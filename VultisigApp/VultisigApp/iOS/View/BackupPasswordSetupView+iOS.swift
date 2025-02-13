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
                BackupVaultSuccessView(vault: vault)
            }
    }
    
    var view: some View {
        VStack {
            animation.view()
                .padding(.top, 42)
            Spacer()
            buttons
        }
    }
    
    var saveButton: some View {
        Button(action: {
            export()
        }) {
            FilledButton(title: "Back Up Now", icon: "square.and.arrow.down")
        }
        .sheet(isPresented: $showSaveShareSheet) {
            if let fileURL = backupViewModel.encryptedFileURLWithPassowrd {
                ShareSheetViewController(activityItems: [fileURL]) { didSave in
                    if didSave {
                        fileSaved()
                        dismissView()
                    }
                }
                .presentationDetents([.medium])
                .ignoresSafeArea(.all)
            }
        }
    }
}
#endif
