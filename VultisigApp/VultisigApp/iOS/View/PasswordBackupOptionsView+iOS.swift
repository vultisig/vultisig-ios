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
    
    @ViewBuilder
    var withoutPasswordButton: some View {
        if let fileURL = backupViewModel.encryptedFileURLWithoutPassowrd {
            Button {
                showSkipShareSheet = true
            } label: {
                withoutPasswordLabel
            }
            .shareSheet(isPresented: $showSkipShareSheet, activityItems: [fileURL])  { didSave in
                if didSave {
                    fileSaved()
                    dismissView()
                }
            }
        }
    }
}
#endif
