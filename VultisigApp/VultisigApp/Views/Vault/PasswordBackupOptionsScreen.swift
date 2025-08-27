//
//  PasswordBackupOptionsScreen.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-03-21.
//

import SwiftUI

struct PasswordBackupOptionsScreen: View {
    let tssType: TssType
    let vault: Vault
    var isNewVault = false
    
    @State var showSkipShareSheet = false
    @State var homeLinkActive = false
    @State var navigationLinkActive = false
    @StateObject var backupViewModel = EncryptedBackupViewModel()
    @State var fileURL: URL?
    
    var body: some View {
        Screen {
            VStack(spacing: 36) {
                Spacer()
                icon
                textContent
                fileExporterContainer {
                    buttons
                }
                Spacer()
            }
        }
        .sensoryFeedback(.success, trigger: vault.isBackedUp)
        .navigationDestination(isPresented: $homeLinkActive) {
            HomeView(selectedVault: vault)
        }
        .navigationDestination(isPresented: $navigationLinkActive) {
            BackupVaultSuccessView(tssType: tssType, vault: vault)
        }
        .onLoad(perform: onLoad)
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
    }
    
    var withoutPasswordButton: some View {
        PrimaryButton(title: "backupWithoutPassword") {
            fileURL = backupViewModel.encryptedFileURLWithoutPassword
            showSkipShareSheet = true
        }
    }
    
    var withPasswordButton: some View {
        PrimaryButton(title: "useMyVaultPassword", type: .secondary) {
            fileURL = backupViewModel.encryptedFileURLWithPassword
            showSkipShareSheet = true
        }
    }
    
    private func onLoad() {
        FileManager.default.clearTmpDirectory()
        backupViewModel.resetData()
        backupViewModel.exportFile(vault)
    }
    
    func fileSaved() {
        vault.isBackedUp = true
        FileManager.default.clearTmpDirectory()
    }
    
    func dismissView() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if isNewVault {
                navigationLinkActive = true
            } else {
                homeLinkActive = true
            }
        }
    }
}

#if os(iOS)
extension PasswordBackupOptionsScreen {
    func fileExporterContainer<Content: View>(_ contentBuilder: () -> Content) -> some View {
        contentBuilder()
            .unwrap(fileURL) { view, url in
                view.shareSheet(isPresented: $showSkipShareSheet, activityItems: [url])  { didSave in
                    if didSave {
                        fileSaved()
                        dismissView()
                    }
                }
            }
        
    }
}
#elseif os(macOS)
extension PasswordBackupOptionsScreen {
    func fileExporterContainer<Content: View>(_ contentBuilder: () -> Content) -> some View {
        contentBuilder()
            .unwrap(fileURL) { view, url in
                view.fileExporter(
                    isPresented: $showSkipShareSheet,
                    document: EncryptedDataFile(url: url),
                    contentType: .data,
                    defaultFilename: "\(vault.getExportName())"
                ) { result in
                    switch result {
                    case .success(let url):
                        print("File saved to: \(url)")
                        fileSaved()
                        dismissView()
                    case .failure(let error):
                        print("Error saving file: \(error.localizedDescription)")
                        backupViewModel.alertTitle = "errorSavingFile"
                        backupViewModel.showAlert = true
                    }
                }
            }
    }
}
#endif

#Preview {
    PasswordBackupOptionsScreen(tssType: .Keygen, vault: Vault.example)
}
