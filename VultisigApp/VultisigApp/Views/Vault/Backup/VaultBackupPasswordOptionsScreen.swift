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
    @State var presentPasswordScreen = false
    @StateObject var backupViewModel = EncryptedBackupViewModel()
    @State var fileModel: FileExporterModel<EncryptedDataFile>?
    
    var body: some View {
        VaultBackupContainerView(
            presentFileExporter: $presentFileExporter,
            fileModel: $fileModel,
            backupViewModel: backupViewModel,
            tssType: tssType,
            vault: vault,
            isNewVault: isNewVault
        ) {
            Screen {
                VStack(spacing: 36) {
                    Spacer()
                    icon
                    textContent
                    buttons
                    Spacer()
                }
            }
        }
        .navigationDestination(isPresented: $presentPasswordScreen) {
            VaultBackupPasswordScreen(tssType: tssType, vault: vault, isNewVault: isNewVault)
        }
        .onAppear(perform: onAppear)
        .onDisappear(perform: backupViewModel.resetData)
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
        fileModel = backupViewModel.exportFileWithoutPassword(vault)
        isLoading = false
    }
}

#Preview {
    VaultBackupPasswordOptionsScreen(tssType: .Keygen, vault: Vault.example)
}
