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
        container
    }
    
    var content: some View {
        VStack(spacing: 22) {
            title
            image
            disclaimer
            Spacer()
            backupDisclaimer
            description
            buttons
        }
        .font(.body12Montserrat)
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
            .padding(.horizontal, 22)
            .font(.body16MontserratBold)
    }
    
    var backupDisclaimer: some View {
        HStack(spacing: 24) {
            icon
            
            Text(NSLocalizedString("backupVaultOnEveryDeviceIndividually!", comment: ""))
                .lineLimit(2)
                .foregroundColor(.neutral0)
            
            icon
        }
        .padding(12)
        .background(Color.alertRed.opacity(0.2))
        .cornerRadius(12)
        .overlay (
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.alertRed, lineWidth: 1)
        )
        .padding(.horizontal, 22)
    }
    
    var icon: some View {
        Image(systemName: "exclamationmark.triangle")
            .font(.body20Menlo)
            .foregroundColor(.alertRed)
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
            BackupPasswordSetupView(vault: vault, isNewVault: true)
        } label: {
            FilledButton(title: "Backup")
        }
    }
    
    var skipButton: some View {
        NavigationLink {
            HomeView(selectedVault: vault, showVaultsList: false, shouldJoinKeygen: false)
        } label: {
            OutlineButton(title: "skip")
        }
    }
}

#Preview {
    BackupVaultNowView(vault: Vault.example)
}
