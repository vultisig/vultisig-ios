//
//  BackupPasswordSetupView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-13.
//

import SwiftUI

struct BackupPasswordSetupView: View {
    let vault: Vault
    
    @StateObject var backupViewModel = EncryptedBackupViewModel()
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            Background()
            view
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString("backup", comment: "Backup"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationBackButton()
            }
        }
        .alert(isPresented: $backupViewModel.showAlert) {
            alert
        }
    }
    
    var view: some View {
        VStack {
            content
            Spacer()
            buttons
        }
        .fileExporter(
            isPresented: $backupViewModel.showVaultExporter,
            document: EncryptedDataFile(url: backupViewModel.encryptedFileURL),
            contentType: .data,
            defaultFilename: "\(vault.getExportName())"
        ) { result in
            switch result {
            case .success(let url):
                print("File saved to: \(url)")
                dismiss()
            case .failure(let error):
                print("Error saving file: \(error.localizedDescription)")
                backupViewModel.alertMessage = error.localizedDescription
                backupViewModel.showAlert = true
            }
        }
    }
    
    var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("passwordProtectBackup", comment: ""))
                .font(.body14MontserratMedium)
                .foregroundColor(.neutral0)
            
            textfield
        }
        .padding(.horizontal, 16)
        .padding(.top, 30)
    }
    
    var textfield: some View {
        SecureField(NSLocalizedString("enterPassword", comment: "").capitalized, text: $backupViewModel.encryptionPassword)
            .font(.body16Menlo)
            .foregroundColor(.neutral0)
            .submitLabel(.done)
            .padding(12)
            .background(Color.blue600)
            .cornerRadius(12)
            .colorScheme(.dark)
    }
    
    var buttons: some View {
        VStack(spacing: 20) {
            saveButton
            skipButton
        }
        .padding(40)
    }
    
    var saveButton: some View {
        Button {
            backupViewModel.exportFile(vault)
        } label: {
            FilledButton(title: "save")
        }
    }
    
    var skipButton: some View {
        Button {
            backupViewModel.encryptionPassword = ""
            backupViewModel.exportFile(vault)
        } label: {
            OutlineButton(title: "skip")
        }
    }
    
    var alert: Alert {
        Alert(
            title: Text(NSLocalizedString("errorSavingFile", comment: "")),
            message: Text(backupViewModel.alertMessage),
            dismissButton: .default(Text(NSLocalizedString("ok", comment: "")))
        )
    }
}

#Preview {
    BackupPasswordSetupView(vault: Vault.example)
}
