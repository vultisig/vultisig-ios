//
//  BackupVaultNowView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-05.
//

import SwiftUI

struct BackupVaultNowView: View {
    let vault: Vault
    
    var body: some View {
        ZStack {
            Background()
            view
        }
        .navigationBarBackButtonHidden(true)
    }
    
    var view: some View {
        VStack(spacing: 36) {
            title
            image
            disclaimer
            description
            Spacer()
            buttons
        }
        .font(.body14MontserratMedium)
        .foregroundColor(.neutral0)
        .multilineTextAlignment(.center)
    }
    
    var title: some View {
        Image("LogoWithTitle")
            .padding(.top, 30)
    }
    
    var image: some View {
        Image("BackupNowImage")
            .offset(x: 5)
    }
    
    var disclaimer: some View {
        Text(NSLocalizedString("pleaseBackupVault", comment: ""))
            .padding(.horizontal, 80)
    }
    
    var description: some View {
        Text(NSLocalizedString("pleaseBackupVaultNote", comment: ""))
            .padding(.horizontal, 60)
    }
    
    var buttons: some View {
        VStack {
            backupButton
            skipButton
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 10)
    }
    
    var backupButton: some View {
        NavigationLink {
            BackupPasswordSetupView(vault: vault)
        } label: {
            FilledButton(title: "Backup")
        }
    }
    
    var skipButton: some View {
        NavigationLink {
            HomeView(selectedVault: vault, showVaultsList: false, shouldJoinKeygen: false)
        } label: {
            skipButtonLabel
        }
    }
    
    var skipButtonLabel: some View {
        Text(NSLocalizedString("skip", comment: ""))
            .padding(12)
            .frame(maxWidth: .infinity)
            .foregroundColor(Color.turquoise600)
            .font(.body16MontserratMedium)
    }
}

#Preview {
    BackupVaultNowView(vault: Vault.example)
}
