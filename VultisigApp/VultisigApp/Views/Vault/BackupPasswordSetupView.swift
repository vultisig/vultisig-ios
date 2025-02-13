//
//  BackupPasswordSetupView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-13.
//

import SwiftUI
import RiveRuntime

struct BackupPasswordSetupView: View {
    let vault: Vault
    var isNewVault = false

    @State var navigationLinkActive = false
    
    @StateObject var backupViewModel = EncryptedBackupViewModel()
    @State var showSkipShareSheet = false
    @State var showSaveShareSheet = false

    let animation = RiveViewModel(fileName: "backupvault_splash.riv", autoPlay: true)

    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        mainContent
    }
    
    var mainContent: some View {
        content
            .onAppear {
                backupViewModel.resetData()
            }
            .onDisappear {
                backupViewModel.resetData()
            }
    }
    
    var buttons: some View {
        saveButton
            .padding(.bottom, 40)
            .padding(.horizontal, 16)
    }

    func export() {
        backupViewModel.exportFile(vault)
    }
    
    func fileSaved() {
        vault.isBackedUp = true
    }
    
    func dismissView() {
        if isNewVault {
            navigationLinkActive = true
        } else {
            dismiss()
        }
    }

    private var labels: some View {
        VStack(spacing: 0) {
            Text("Back up your vault\nshare online")
                .font(.body34BrockmannMedium)
                .foregroundColor(Color.neutral0)
                .padding(.bottom, 16)

            Text("Online storage is recommended and safe -\nvault shares are designed for this.")
                .font(.body14BrockmannMedium)
                .foregroundColor(Color.extraLightGray)

            Button {

            } label: {
                Text("Learn more")
                    .font(.body14BrockmannMedium)
                    .foregroundColor(Color.lightText)
                    .underline()
            }
        }
    }
}

#Preview {
    BackupPasswordSetupView(vault: Vault.example)
}
