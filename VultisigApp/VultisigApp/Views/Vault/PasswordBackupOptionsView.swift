//
//  PasswordBackupOptionsView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-03-21.
//

import SwiftUI

struct PasswordBackupOptionsView: View {
    let tssType: TssType
    let vault: Vault
    var isNewVault = false
    
    @State var showSkipShareSheet = false
    @State var homeLinkActive = false
    @State var navigationLinkActive = false
    @StateObject var backupViewModel = EncryptedBackupViewModel()
    
    var body: some View {
        ZStack {
            Background()
            content
        }
        .navigationDestination(isPresented: $homeLinkActive) {
            HomeView(selectedVault: vault)
        }
        .navigationDestination(isPresented: $navigationLinkActive) {
            BackupVaultSuccessView(tssType: tssType, vault: vault)
        }
        .onAppear {
            backupViewModel.resetData()
            handleSkipTap()
        }
        .onDisappear {
            backupViewModel.resetData()
        }
    }
    
    var icon: some View {
        Image(systemName: "person.badge.key")
            .font(.body28BrockmannMedium)
            .foregroundColor(.neutral0)
            .frame(width: 64, height: 64)
            .background(Color.blue400)
            .cornerRadius(16)
    }
    
    var textContent: some View {
        VStack(spacing: 16) {
            Text(NSLocalizedString("doYouWantToAddPassword", comment: ""))
                .font(.body22BrockmannMedium)
            
            Text(NSLocalizedString("doYouWantToAddPasswordDescription", comment: ""))
                .font(.body14BrockmannMedium)
                .opacity(0.6)
        }
        .foregroundColor(.neutral0)
        .multilineTextAlignment(.center)
    }
    
    var buttons: some View {
        VStack(spacing: 12) {
            withoutPasswordButton
            withPasswordButton
        }
    }
    
    var withoutPasswordLabel: some View {
        FilledButton(title: "backupWithoutPassword")
    }
    
    var withPasswordButton: some View {
        NavigationLink {
            BackupPasswordSetupView(
                tssType: tssType,
                vault: vault,
                isNewVault: isNewVault,
                showSkipPasswordButton: false
            )
        } label: {
            withPasswordLabel
        }
    }
    
    var withPasswordLabel: some View {
        FilledButton(
            title: "usePassword",
            textColor: .neutral0,
            background: .blue400
        )
    }
    
    private func handleSkipTap() {
        backupViewModel.encryptionPassword = ""
        backupViewModel.exportFile(vault)
    }
    
    func fileSaved() {
        vault.isBackedUp = true
    }
    
    func dismissView() {
        if isNewVault {
            navigationLinkActive = true
        } else {
            homeLinkActive = true
        }
    }
}

#Preview {
    PasswordBackupOptionsView(tssType: .Keygen, vault: Vault.example)
}
