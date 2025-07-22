//
//  BackupPasswordSetupView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-13.
//

import SwiftUI
import RiveRuntime

struct BackupSetupView: View {
    let tssType: TssType
    let vault: Vault
    var isNewVault = false

    @State var navigationLinkActive = false

    @State var showSkipShareSheet = false
    @State var showSaveShareSheet = false

    @State var animation: RiveViewModel?

    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        mainContent
            .navigationDestination(isPresented: $navigationLinkActive) {
                PasswordBackupOptionsView(tssType: tssType, vault: vault, isNewVault: isNewVault)
            }
            .onAppear {
                animation = RiveViewModel(fileName: "backupvault_splash", autoPlay: true)
            }
    }
    
    var mainContent: some View {
        content
    }
    
    var buttons: some View {
        saveButton
            .padding(.bottom, 40)
            .padding(.horizontal, 16)
    }

    var saveButton: some View {
        PrimaryButton(title: "backupNow", leadingIcon: "square.and.arrow.down") {
            navigationLinkActive = true
        }
    }

    var labels: some View {
        VStack(spacing: 0) {
            Text(NSLocalizedString("backupSetupTitle", comment: ""))
                .font(.body34BrockmannMedium)
                .foregroundColor(Color.neutral0)
                .padding(.bottom, 16)
                .multilineTextAlignment(.center)

            Text(NSLocalizedString("backupSetupSubtitle", comment: ""))
                .font(.body14BrockmannMedium)
                .foregroundColor(Color.extraLightGray)
                .multilineTextAlignment(.center)

            Button {
                // TODO: Learn more link
            } label: {
                Text(NSLocalizedString("learnMore", comment: ""))
                    .font(.body14BrockmannMedium)
                    .foregroundColor(Color.lightText)
                    .underline()
            }
        }
    }
}

#Preview {
    BackupPasswordSetupView(tssType: .Keygen, vault: Vault.example)
}
