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
    let backupType: VaultBackupType
    var isNewVault = false

    @StateObject var backupViewModel = EncryptedBackupViewModel()
    @State var presentBackupOptions = false
    @State var animation: RiveViewModel?
    @State var fileModel: FileExporterModel<EncryptedDataFile>?
    @State var presentFileExporter = false
   
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
                VStack {
                    animation?.view()
                    labels
                    Spacer().frame(height: 100)
                    PrimaryButton(title: "backupNow", leadingIcon: "square.and.arrow.down") {
                        onBackupNow()
                    }
                }
            }
        }
        .navigationDestination(isPresented: $presentBackupOptions) {
            VaultBackupPasswordOptionsScreen(tssType: tssType, backupType: backupType, isNewVault: isNewVault)
        }
        .onLoad(perform: onLoad)
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
        
        if backupType.vault.isFastVault, isNewVault {
            fileModel = backupViewModel.exportFileWithVaultPassword(backupType)
        }
    }
    
    func onBackupNow() {
        // Only export backup directly if it's fast vault during creation
        guard backupType.vault.isFastVault, isNewVault, fileModel != nil else {
            presentBackupOptions = true
            return
        }
        
        presentFileExporter = true
    }
}

#Preview {
    VaultBackupNowScreen(tssType: .Keygen, backupType: .single(vault: .example))
}
