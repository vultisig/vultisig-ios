//
//  BackupVaultNowView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-05.
//

import SwiftUI

struct BackupVaultNowView: View {
    let vault: Vault
    @State var isHomeAfterSkipShown = false

    var body: some View {
        ZStack {
            Background()
            view
        }
        .navigationBarBackButtonHidden(true)
    }
    
    var view: some View {
        container
            .navigationDestination(isPresented: $isHomeAfterSkipShown) {
                HomeView(selectedVault: vault, showVaultsList: false, shouldJoinKeygen: false)
            }
    }
    
    var content: some View {
        VStack(spacing: 0) {
            logo
            image
            title
            Spacer()
            disclaimer
            Spacer()
            description
            Spacer()
            backupButton
        }
        .font(Theme.fonts.bodySRegular)
        .foregroundColor(Theme.colors.textPrimary)
        .multilineTextAlignment(.center)
    }

    var logo: some View {
        Image("LogoWithTitle")
            .padding(.top, 30)
    }

    var title: some View {
        Text(NSLocalizedString("backupNowTitle", comment: ""))
            .foregroundColor(Theme.colors.textPrimary)
            .font(Theme.fonts.title2)
            .fixedSize(horizontal: false, vertical: true)
    }

    var image: some View {
        Image("BackupNowImage")
            .offset(x: 5)
            .padding(.bottom, 6)
    }

    var disclaimer: some View {
        WarningView(text: NSLocalizedString("backupNowWarning", comment: ""))
            .padding(.horizontal, 16)
            .fixedSize(horizontal: false, vertical: true)
    }

    var description: some View {
        Text(NSLocalizedString("backupNowSubtitle", comment: ""))
            .padding(.horizontal, 32)
            .multilineTextAlignment(.center)
    }
    
    var backupButton: some View {
        PrimaryNavigationButton(title: "Backup") {
            VaultBackupNowScreen(tssType: .Keygen, vault: vault, isNewVault: true)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 40)
        .padding(.bottom, 10)
    }
}

#Preview {
    BackupVaultNowView(vault: Vault.example)
}
