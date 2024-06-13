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
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
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
                if let url = urls.first {
                    backupViewModel.importFile(from: url)
                }
            case .failure(let error):
                print("Error importing file: \(error.localizedDescription)")
            }
        }
//        .navigationDestination(isPresented: $viewModel.isLinkActive) {
//            HomeView()
//        }
        .onAppear {
            backupViewModel.resetData()
        }
        .onDisappear {
            backupViewModel.resetData()
        }
    }
    
    var view: some View {
        VStack(spacing: 15) {
            instruction
            uploadSection
            
//            if let filename = viewModel.filename {
//                fileCell(filename)
//            }
            
            Spacer()
            continueButton
        }
        .padding(.top, 30)
        .padding(.horizontal, 30)
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
    }
    
    var continueButton: some View {
        Button {
//            viewModel.restoreVault(modelContext: context,vaults: vaults)
        } label: {
            FilledButton(title: "continue")
//                .disabled(!viewModel.isFileUploaded)
//                .grayscale(viewModel.isFileUploaded ? 0 : 1)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 40)
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
            backupViewModel.resetData()
        } label: {
            Image(systemName: "xmark")
                .font(.body16MontserratMedium)
                .foregroundColor(.neutral0)
                .padding(8)
        }
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
}

#Preview {
    ImportWalletView()
}
