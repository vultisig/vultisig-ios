//
//  VaultBackupPasswordOptionsScreen.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-03-21.
//

import SwiftUI

struct VaultBackupPasswordOptionsScreen: View {
    let tssType: TssType
    let vault: Vault
    var isNewVault = false
    
    @State var isLoading = false
    @State var presentFileExporter = false
    @State var presentHome = false
    @State var presentSuccess = false
    @State var presentPasswordScreen = false
    @StateObject var backupViewModel = EncryptedBackupViewModel()
    @State var fileModelWithoutPassword: FileExporterModel?
    
    var body: some View {
        Screen {
            VStack(spacing: 36) {
                Spacer()
                icon
                textContent
                buttons
                Spacer()
            }
        }
        .sensoryFeedback(.success, trigger: vault.isBackedUp)
        .navigationDestination(isPresented: $presentHome) {
            HomeView(selectedVault: vault)
        }
        .navigationDestination(isPresented: $presentSuccess) {
            BackupVaultSuccessView(tssType: tssType, vault: vault)
        }
        .navigationDestination(isPresented: $presentPasswordScreen) {
            VaultBackupPasswordScreen(tssType: tssType, vault: vault, isNewVault: isNewVault)
        }
        .onAppear(perform: onAppear)
        .onDisappear(perform: backupViewModel.resetData)
        .fileExporter(isPresented: $presentFileExporter, fileModel: $fileModelWithoutPassword) { result in
            switch result {
            case .success(let didSave):
                if didSave {
                    fileSaved()
                    dismissView()
                }
            case .failure(let error):
                print("Error saving file: \(error.localizedDescription)")
                backupViewModel.alertTitle = "errorSavingFile"
                backupViewModel.showAlert = true
            }
        }
    }
    
    var icon: some View {
        Image(systemName: "person.badge.key")
            .font(Theme.fonts.title1)
            .foregroundColor(Theme.colors.textPrimary)
            .frame(width: 64, height: 64)
            .background(Theme.colors.bgTertiary)
            .cornerRadius(16)
    }
    
    var textContent: some View {
        VStack(spacing: 16) {
            Text(NSLocalizedString("doYouWantToAddPassword", comment: ""))
                .font(Theme.fonts.title2)
            
            Text(NSLocalizedString("doYouWantToAddPasswordDescription", comment: ""))
                .font(Theme.fonts.bodySMedium)
                .opacity(0.6)
        }
        .foregroundColor(Theme.colors.textPrimary)
        .multilineTextAlignment(.center)
    }
    
    var buttons: some View {
        VStack(spacing: 12) {
            withoutPasswordButton
            withPasswordButton
        }
        .disabled(isLoading)
    }
    
    var withoutPasswordButton: some View {
        PrimaryButton(title: "backupWithoutPassword") {
            presentFileExporter = true
        }
    }
    
    var withPasswordButton: some View {
        PrimaryButton(title: "usePassword", type: .secondary) {
            presentPasswordScreen = true
        }
    }
    
    private func onAppear() {
        isLoading = true
        FileManager.default.clearTmpDirectory()
        backupViewModel.resetData()
        fileModelWithoutPassword = backupViewModel.exportFileWithoutPassword(vault)
        isLoading = false
    }
    
    func fileSaved() {
        vault.isBackedUp = true
        FileManager.default.clearTmpDirectory()
    }
    
    func dismissView() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if isNewVault {
                presentSuccess = true
            } else {
                presentHome = true
            }
        }
    }
}

#Preview {
    VaultBackupPasswordOptionsScreen(tssType: .Keygen, vault: Vault.example)
}
