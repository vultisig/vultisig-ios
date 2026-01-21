//
//  VaultBackupContainerView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 28/08/2025.
//

import SwiftUI

struct VaultBackupContainerView<Content: View>: View {
    @Binding var presentFileExporter: Bool
    @Binding var fileModel: FileExporterModel<EncryptedDataFile>?
    @ObservedObject var backupViewModel: EncryptedBackupViewModel

    let tssType: TssType
    let backupType: VaultBackupType
    let isNewVault: Bool
    var content: () -> Content

    @Environment(\.router) var router

    @EnvironmentObject var appViewModel: AppViewModel

    var body: some View {
        content()
            .sensoryFeedback(.success, trigger: backupType.vault.isBackedUp)
            .fileExporter(isPresented: $presentFileExporter, fileModel: $fileModel) { result in
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
            .alert(isPresented: $backupViewModel.showAlert) {
                Alert(
                    title: Text(NSLocalizedString(backupViewModel.alertTitle, comment: "")),
                    message: Text(""),
                    dismissButton: .default(Text(NSLocalizedString("ok", comment: "")))
                )
            }
    }

    func fileSaved() {
        backupType.markBackedUp()
        FileManager.default.clearTmpDirectory()
    }

    func dismissView() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if isNewVault {
                router.navigate(to: VaultRoute.backupSuccess(
                    tssType: tssType,
                    vault: backupType.vault
                ))
            } else {
                appViewModel.set(selectedVault: backupType.vault)
            }
        }
    }
}
