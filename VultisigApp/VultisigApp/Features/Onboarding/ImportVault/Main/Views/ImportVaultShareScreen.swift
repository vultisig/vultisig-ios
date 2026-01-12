//
//  ImportWalletView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-07.
//

import SwiftUI
import SwiftData

struct ImportVaultShareScreen: View {
    @Environment(\.modelContext) private var context
    @StateObject var backupViewModel = EncryptedBackupViewModel()
    
    @State var isUploading: Bool = false
    
    @Query var vaults: [Vault]
    @EnvironmentObject var vultExtensionViewModel: VultExtensionViewModel
    @EnvironmentObject var appViewModel: AppViewModel
    
    var body: some View {
        Screen(title: "importVault".localized) {
            content
        }
        .fileImporter(
            isPresented: $backupViewModel.showVaultImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            backupViewModel.handleFileImporter(result)
        }
        .onChange(of: backupViewModel.isVaultImported) { _, isVaultImported in
            guard isVaultImported else { return }
            appViewModel.showOnboarding = false
            appViewModel.set(selectedVault: backupViewModel.selectedVault)
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
            HStack(spacing: 0) {
                instruction
                Spacer()
                resetButton
                    .showIf(backupViewModel.isFileUploaded)
            }
            Spacer()
            continueButton
        }
    }
    
    var instruction: some View {
        Text(NSLocalizedString("supportedFileTypesUpload", comment: ""))
            .font(Theme.fonts.caption12)
            .foregroundColor(Theme.colors.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var resetButton: some View {
        Button {
            resetData()
        } label: {
            Icon(named: "x", color: Theme.colors.textPrimary, size: 16)
                .padding(6)
                .background(Circle().fill(Theme.colors.bgSurface2))
        }
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
        .disabled(!backupViewModel.isFileUploaded)
    }
    
    private func setData() {
        resetData()
        
        if let data = vultExtensionViewModel.documentData, let url = data.fileURL {
            backupViewModel.handleFileDocument(url)
            vultExtensionViewModel.documentData = nil
        }
        
        if let url = vultExtensionViewModel.documentUrl {
            backupViewModel.handleFileDocument(url)
            vultExtensionViewModel.documentUrl = nil
        }
    }
    
    private func resetData() {
        backupViewModel.resetData()
    }
    
    private func handleButtonTap() {
        // Check if this is a multiple vault import from zip
        if backupViewModel.isMultipleVaultImport {
            backupViewModel.restoreMultipleVaults(
                modelContext: context,
                vaults: vaults
            )
        } else {
            // Single vault import
            backupViewModel.restoreVault(
                modelContext: context,
                vaults: vaults
            )
        }
        
        if !backupViewModel.showAlert {
            vultExtensionViewModel.showImportView = false
        }
    }
}

#Preview {
    ImportVaultShareScreen()
        .environmentObject(VultExtensionViewModel())
        .environmentObject(AppViewModel())
}
