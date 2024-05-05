//
//  ImportWalletView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-07.
//

import SwiftUI
import UniformTypeIdentifiers

struct ImportWalletView: View {
    @Environment(\.modelContext) private var context
    @StateObject var viewModel = ImportVaultViewModel()
    @State var showFileImporter = false
    
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
            isPresented: $showFileImporter,
            allowedContentTypes: [UTType.data],
            allowsMultipleSelection: false
        ) { result in
            viewModel.readFile(for: result)
        }
        .navigationDestination(isPresented: $viewModel.isLinkActive) {
            HomeView()
        }
        .alert(isPresented: $viewModel.showAlert) {
            Alert(
                title: Text(NSLocalizedString("error", comment: "")),
                message: Text(viewModel.errorMessage),
                dismissButton: .default(Text("ok"))
            )
        }
        .onDisappear {
            viewModel.removeFile()
        }
    }
    
    var view: some View {
        VStack(spacing: 15) {
            instruction
            uploadSection
            
            if let filename = viewModel.filename {
                fileCell(filename)
            }
            
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
            showFileImporter.toggle()
        } label: {
            ImportWalletUploadSection(viewModel: viewModel)
        }
    }
    
    var continueButton: some View {
        Button {
            viewModel.restoreVault(modelContext: context)
        } label: {
            FilledButton(title: "continue")
                .disabled(!viewModel.isFileUploaded)
                .grayscale(viewModel.isFileUploaded ? 0 : 1)
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
            viewModel.removeFile()
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
