//
//  VaultBackupPasswordOptionsScreen.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-03-21.
//

import SwiftUI

struct VaultBackupPasswordOptionsScreen: View {
    let tssType: TssType
    let backupType: VaultBackupType
    var isNewVault = false
    
    @State var isLoading = false
    @State var presentFileExporter = false
    @StateObject var backupViewModel = EncryptedBackupViewModel()
    @State var fileModel: FileExporterModel<EncryptedDataFile>?
    @Environment(\.router) var router

    var body: some View {
        VaultBackupContainerView(
            presentFileExporter: $presentFileExporter,
            fileModel: $fileModel,
            backupViewModel: backupViewModel,
            tssType: tssType,
            backupType: backupType,
            isNewVault: isNewVault
        ) {
            Screen {
                VStack(spacing: 36) {
                    icon
                    textContent
                    Spacer()
                    buttons
                }
            }
        }
        .onAppear(perform: onAppear)
        .onDisappear(perform: backupViewModel.resetData)
    }
    
    var icon: some View {
        Image(systemName: "person.badge.key")
            .font(Theme.fonts.title1)
            .foregroundColor(Theme.colors.textPrimary)
            .frame(width: 64, height: 64)
            .background(Theme.colors.bgSurface2)
            .cornerRadius(16)
    }
    
    var textContent: some View {
        VStack(spacing: 16) {
            Text("backupOptionsTitle".localized)
                .font(Theme.fonts.title2)
                .foregroundColor(Theme.colors.textPrimary)
                .multilineTextAlignment(.center)
            
            boxedText("backupOptionsBox1".localized, highlighted: "backupOptionsBox1Highlighted".localized, icon: "lock-keyhole-open")
            
            boxedText("backupOptionsBox2".localized, highlighted: "backupOptionsBox2Highlighted".localized, icon: "folder-lock")
            
            boxedText("backupOptionsBox3".localized, highlighted: "backupOptionsBox3Highlighted".localized, icon: "file-warning")
        }
    }
    
    func boxedText(_ text: String, highlighted: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Icon(named: icon, color: Theme.colors.primaryAccent4, size: 24)
            HighlightedText(text: String(format: text.localized, highlighted), highlightedText: highlighted) {
                $0.foregroundColor = Theme.colors.textTertiary
                $0.font = Theme.fonts.footnote
            } highlightedTextStyle: {
                $0.foregroundColor = Theme.colors.textPrimary
                $0.font = Theme.fonts.footnote
            }
        }
        .frame(maxWidth: 325)
        .containerStyle(padding: 16, bgColor: Theme.colors.bgSurface1)
        
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
            router.navigate(to: VaultRoute.backupPasswordScreen(
                tssType: tssType,
                backupType: backupType,
                isNewVault: isNewVault
            ))
        }
    }
    
    private func onAppear() {
        isLoading = true
        FileManager.default.clearTmpDirectory()
        backupViewModel.resetData()
        Task {
            let fileModel = await backupViewModel.exportFileWithoutPassword(backupType)
            await MainActor.run {
                isLoading = false
                self.fileModel = fileModel
            }
        }
    }
}

#Preview {
    VaultBackupPasswordOptionsScreen(tssType: .Keygen, backupType: .single(vault: Vault.example))
}
