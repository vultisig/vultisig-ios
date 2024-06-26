//
//  ImportWalletView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-07.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ImportWalletView: View {
    @Environment(\.modelContext) private var context
    @StateObject var backupViewModel = EncryptedBackupViewModel()
    
    @Query var vaults: [Vault]
    
    var body: some View {
        ZStack {
            Background()
            view
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString("import", comment: "Import title"))
        .toolbar {
            ToolbarItem(placement: .navigation) {
                NavigationBackButton()
            }
        }
        .fileImporter(
            isPresented: $backupViewModel.showVaultImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard isValidFormat(urls) else {
                    showInvalidFormatAlert()
                    return
                }
                
                if let url = urls.first {
                    backupViewModel.importedFileName = url.lastPathComponent
                    backupViewModel.importFile(from: url)
                }
            case .failure(let error):
                print("Error importing file: \(error.localizedDescription)")
            }
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
            ImportWalletUploadSection(viewModel: backupViewModel)
        }
        .buttonStyle(PlainButtonStyle())
        .background(Color.clear)
    }
    
    var continueButton: some View {
        Button {
            backupViewModel.restoreVault(modelContext: context,vaults: vaults)
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
    
    var fileImage: some View {
        Image("FileIcon")
            .resizable()
            .frame(width: 24, height: 24)
    }
    
    func fileName(_ name: String) -> some View {
        Text(name)
            .font(.body12Menlo)
            .foregroundColor(.neutral0)
    }
    
    var closeButton: some View {
        Button {
            resetData()
        } label: {
            Image(systemName: "xmark")
                .font(.body16MontserratMedium)
                .foregroundColor(.neutral0)
                .padding(8)
        }
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
        HStack {
            fileImage
            fileName(name)
            Spacer()
            closeButton
        }
        .padding(12)
    }
    
    private func resetData() {
        backupViewModel.resetData()
    }
    
    private func isValidFormat(_ urls: [URL]) -> Bool {
        guard let fileExtension = urls.first?.pathExtension.lowercased() else {
            return false
        }
        
        if fileExtension == "dat" {
            return true
        } else {
            return false
        }
    }
    
    private func showInvalidFormatAlert() {
        backupViewModel.alertTitle = "invalidFileFormat"
        backupViewModel.alertMessage = "invalidFileFormatMessage"
        backupViewModel.showAlert = true
    }
}

#Preview {
    ImportWalletView()
}
