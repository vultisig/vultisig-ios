//
//  BackupPasswordSetupView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-13.
//

import SwiftUI
import RiveRuntime

struct VaultBackupNowScreen: View {
    let tssType: TssType
    let vault: Vault
    var isNewVault = false

    @StateObject var backupViewModel = EncryptedBackupViewModel()
    @State var presentBackupOptions = false
    @State var presentHome = false
    @State var presentBackupSuccess = false
    @State var animation: RiveViewModel?
    @State var fileModel: FileExporterModel?
    @State var presentFileExporter = false
   
    var body: some View {
        Screen {
            VStack {
                animation?.view()
                labels
                Spacer().frame(height: 100)
                PrimaryButton(title: "backupNow", leadingIcon: "square.and.arrow.down") {
                    onBackupNow()
                }
            }
        }
        .navigationDestination(isPresented: $presentBackupOptions) {
            VaultBackupPasswordOptionsScreen(tssType: tssType, vault: vault, isNewVault: isNewVault)
        }
        .navigationDestination(isPresented: $presentBackupSuccess) {
            BackupVaultSuccessView(tssType: tssType, vault: vault)
        }
        .navigationDestination(isPresented: $presentHome) {
            HomeView(selectedVault: vault)
        }
        .onLoad(perform: onLoad)
        .fileExporter(isPresented: $presentFileExporter, fileModel: $fileModel) { result in
            switch result {
            case .success(let didSave):
                if didSave {
                    fileSaved()
                    dismissView()
                }
            case .failure(let error):
                print("Error saving file: \(error.localizedDescription)")
            }
        }
    }

    var labels: some View {
        VStack(spacing: 0) {
            Text(NSLocalizedString("backupSetupTitle", comment: ""))
                .font(Theme.fonts.largeTitle)
                .foregroundColor(Theme.colors.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 16)

            Text(NSLocalizedString("backupSetupSubtitle", comment: ""))
                .font(Theme.fonts.bodySMedium)
                .foregroundColor(Theme.colors.textExtraLight)
                .multilineTextAlignment(.center)

            Link(destination: StaticURL.VultBackupURL) {
                Text(NSLocalizedString("learnMore", comment: ""))
                    .font(Theme.fonts.bodySMedium)
                    .foregroundColor(Theme.colors.textLight)
                    .underline()
            }
        }
    }
    
    func onLoad() {
        FileManager.default.clearTmpDirectory()
        animation = RiveViewModel(fileName: "backupvault_splash", autoPlay: true)
        
        if vault.isFastVault {
            fileModel = backupViewModel.exportFileWithVaultPassword(vault)
        }
    }
    
    func onBackupNow() {
        guard vault.isFastVault, fileModel != nil else {
            presentBackupOptions = true
            return
        }
        
        presentFileExporter = true
    }
    
    func fileSaved() {
        vault.isBackedUp = true
        FileManager.default.clearTmpDirectory()
    }
    
    func dismissView() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if isNewVault {
                presentBackupSuccess = true
            } else {
                presentHome = true
            }
        }
    }
}

#Preview {
    VaultBackupNowScreen(tssType: .Keygen, vault: Vault.example)
}
