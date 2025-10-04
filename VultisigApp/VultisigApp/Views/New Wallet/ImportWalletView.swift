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
    @EnvironmentObject var vultExtensionViewModel: VultExtensionViewModel
    
    var body: some View {
        content
            .fileImporter(
                isPresented: $backupViewModel.showVaultImporter,
                allowedContentTypes: [.data],
                allowsMultipleSelection: false
            ) { result in
                backupViewModel.handleFileImporter(result)
            }
            .navigationDestination(isPresented: $backupViewModel.isLinkActive) {
                HomeScreen(initialVault: backupViewModel.selectedVault)
            }
            .onAppear {
                setData()
            }
            .onDisappear {
                resetData()
            }
    }

    var view: some View {
        VStack(spacing: 15) {
            Spacer()
            uploadSection
            instruction
            Spacer()
            continueButton
        }
        .padding(.top, 30)
        .padding(.horizontal, 30)
    }
    
    var instruction: some View {
        Text(NSLocalizedString("supportedFileTypesUpload", comment: ""))
            .font(Theme.fonts.caption12)
            .foregroundColor(Theme.colors.textExtraLight)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var uploadSection: some View {
        Button {
            backupViewModel.showVaultImporter.toggle()
        } label: {
            ImportWalletUploadSection(
                viewModel: backupViewModel,
                isUploading: isUploading
            )
        }
        .buttonStyle(PlainButtonStyle())
        .background(Color.clear)
    }
    
    var continueButton: some View {
        PrimaryButton(title: "continue") {
            handleButtonTap()
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 40)
        .disabled(!backupViewModel.isFileUploaded)
    }
    
    private func setData() {
        resetData()
        
        if let data = vultExtensionViewModel.documentData, let url = data.fileURL {
            backupViewModel.handleFileDocument(url)
        }
        
        if let url = vultExtensionViewModel.documentUrl {
            backupViewModel.handleFileDocument(url)
        }
    }
    
    private func resetData() {
        backupViewModel.resetData()
    }
    
    private func handleButtonTap() {
        backupViewModel.restoreVault(
            modelContext: context,
            vaults: vaults,
            defaultChains: settingsDefaultChainViewModel.defaultChains
        )
        
        if !backupViewModel.showAlert {
            vultExtensionViewModel.showImportView = false
        }
    }
}

#Preview {
    ImportWalletView()
        .environmentObject(VultExtensionViewModel())
}
