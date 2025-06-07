//
//  PasswordBackupOptionsView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-03-21.
//

#if os(iOS)
import SwiftUI

extension PasswordBackupOptionsView {
    var content: some View {
        VStack(spacing: 36) {
            icon
            textContent
            buttons
        }
        .padding(24)
    }
    
    var withoutPasswordButton: some View {
        Button {
            showSkipShareSheet = true
        } label: {
            withoutPasswordLabel
        }
        .sheet(isPresented: $showSkipShareSheet) {
            if let fileURL = backupViewModel.encryptedFileURLWithoutPassowrd {
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
