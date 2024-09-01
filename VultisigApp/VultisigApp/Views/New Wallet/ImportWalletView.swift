//
//  ImportWalletView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-07.
//

import SwiftUI
import SwiftData

struct ImportWalletView: View {
    @Environment(\.modelContext) private var context
    @StateObject var backupViewModel = EncryptedBackupViewModel()
    
    @State var isUploading: Bool = false
    
    @Query var vaults: [Vault]
    @EnvironmentObject var settingsDefaultChainViewModel: SettingsDefaultChainViewModel
    
    var body: some View {
        content
            .fileImporter(
                isPresented: $backupViewModel.showVaultImporter,
                allowedContentTypes: [.data],
                allowsMultipleSelection: false
            ) { result in
                backupViewModel.handleFileImporter(result)
            }
            .onDrop(of: [.data], isTargeted: $isUploading) { providers -> Bool in
                backupViewModel.handleOnDrop(providers: providers)
            }
            .navigationDestination(isPresented: $backupViewModel.isLinkActive) {
                HomeView(selectedVault: backupViewModel.selectedVault)
            }
            .onAppear {
                resetData()
            }
            .onDisappear {
                resetData()
            }
    }
    
    var headerMac: some View {
        GeneralMacHeader(title: "import")
    }
    
    var view: some View {
        VStack(spacing: 15) {
            instruction
            uploadSection
            
            if let filename = backupViewModel.importedFileName, backupViewModel.isFileUploaded {
                fileCell(filename)
            }
            
            Spacer()
            continueButton
        }
        .padding(.top, 30)
        .padding(.horizontal, 30)
        .alert(isPresented: $backupViewModel.showAlert) {
            alert
        }
    }
    
    var instruction: some View {
        Text(NSLocalizedString("enterPreviousVault", comment: "Import Vault instruction"))
            .font(.body12Menlo)
            .foregroundColor(.neutral0)
    }
    
    var uploadSection: some View {
        Button {
            backupViewModel.showVaultImporter.toggle()
        } label: {
            ImportWalletUploadSection(viewModel: backupViewModel, isUploading: isUploading)
        }
        .buttonStyle(PlainButtonStyle())
        .background(Color.clear)
    }
    
    var continueButton: some View {
        Button {
            backupViewModel.restoreVault(
                modelContext: context,
                vaults: vaults,
                defaultChains: settingsDefaultChainViewModel.defaultChains
            )
        } label: {
            FilledButton(title: "continue")
                .disabled(!backupViewModel.isFileUploaded)
                .grayscale(backupViewModel.isFileUploaded ? 0 : 1)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 40)
        .buttonStyle(PlainButtonStyle())
        .background(Color.clear)
    }
    
    var alert: Alert {
        Alert(
            title: Text(NSLocalizedString(backupViewModel.alertTitle, comment: "")),
            message: Text(NSLocalizedString(backupViewModel.alertMessage, comment: "")),
            dismissButton: .default(Text(NSLocalizedString("ok", comment: "")))
        )
    }
    
    private func fileCell(_ name: String) -> some View {
        ImportFileCell(name: name, resetData: resetData)
    }
    
    private func resetData() {
        backupViewModel.resetData()
    }
}

#Preview {
    ImportWalletView()
}
