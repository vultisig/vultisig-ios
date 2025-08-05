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

    @State var animation: RiveViewModel?
   
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
                .font(Theme.fonts.largeTitle)
                .foregroundColor(Color.neutral0)
                .padding(.bottom, 16)
                .multilineTextAlignment(.center)

            Text(NSLocalizedString("backupSetupSubtitle", comment: ""))
                .font(Theme.fonts.bodySMedium)
                .foregroundColor(Color.extraLightGray)
                .multilineTextAlignment(.center)

            Link(destination: StaticURL.VultBackupURL) {
                Text(NSLocalizedString("learnMore", comment: ""))
                    .font(Theme.fonts.bodySMedium)
                    .foregroundColor(Color.lightText)
                    .underline()
            }
        }
    }
}

#Preview {
    BackupPasswordSetupView(tssType: .Keygen, vault: Vault.example)
}
