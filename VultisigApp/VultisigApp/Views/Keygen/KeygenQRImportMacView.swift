//
//  KeygenQRImportMacView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-27.
//

import SwiftUI
import SwiftData

struct KeygenQRImportMacView: View {
    @State var fileName: String? = nil
    @State private var selectedImage: NSImage?
    @State var isButtonEnabled = false
    @State var importResult: Result<[URL], Error>? = nil
    
    @State var shouldJoinKeygen = false
    @State var shouldKeysignTransaction = false
    
    @Query var vaults: [Vault]
    
    @EnvironmentObject var deeplinkViewModel: DeeplinkViewModel
    
    var body: some View {
        ZStack {
            Background()
            content
        }
        .navigationTitle("pair")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                NavigationBackButton()
            }
        }
    }
    
    var content: some View {
        VStack(spacing: 32) {
            title
            uploadSection
            Spacer()
            button
        }
        .padding(40)
        .navigationDestination(isPresented: $shouldJoinKeygen) {
            JoinKeygenView(vault: Vault(name: "Main Vault"))
        }
    }
    
    var title: some View {
        Text(NSLocalizedString("uploadQRCodeImageKeygen", comment: ""))
            .font(.body16MontserratBold)
            .foregroundColor(.neutral0)
    }
    
    var uploadSection: some View {
        FileQRCodeImporterMac(
            fileName: fileName, 
            selectedImage: selectedImage,
            resetData: resetData,
            handleFileImport: handleFileImport
        )
    }
    
    var button: some View {
        Button {
            joinKeygen()
        } label: {
            FilledButton(title: "continue")
                .disabled(!isButtonEnabled)
                .grayscale(isButtonEnabled ? 0 : 1)
        }
    }
    
    private func resetData() {
        fileName = nil
        selectedImage = nil
        isButtonEnabled = false
        importResult = nil
    }
    
    private func handleFileImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            setValues(urls)
            importResult = result
        case .failure(let error):
            print("Error importing file: \(error.localizedDescription)")
        }
    }
    
    private func setValues(_ urls: [URL]) {
        do {
            if let url = urls.first {
                let _ = url.startAccessingSecurityScopedResource()
                fileName = url.lastPathComponent
                
                let imageData = try Data(contentsOf: url)
                if let nsImage = NSImage(data: imageData) {
                    selectedImage = nsImage
                }
                isButtonEnabled = true
            }
        } catch {
            print(error)
        }
    }
    
    private func joinKeygen() {
        guard let importResult else {
            return
        }
        
        let qrCode = Utils.handleQrCodeFromImage(result: importResult)
        let result = String(data: qrCode, encoding: .utf8)
        
        guard let result, let url = URL(string: result) else {
            return
        }
        
        deeplinkViewModel.extractParameters(url, vaults: vaults)
        presetValuesForDeeplink(url)
    }
    
    private func presetValuesForDeeplink(_ url: URL) {
        shouldJoinKeygen = false
        shouldKeysignTransaction = false
        
        guard let type = deeplinkViewModel.type else {
            return
        }
        deeplinkViewModel.type = nil
        
        switch type {
        case .NewVault:
            moveToCreateVaultView()
        case .SignTransaction:
            moveToVaultsView()
        case .Unknown:
            return
        }
    }
    
    private func moveToCreateVaultView() {
        shouldJoinKeygen = true
    }
    
    private func moveToVaultsView() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            shouldKeysignTransaction = true
        }
    }
}

#Preview {
    KeygenQRImportMacView()
        .environmentObject(DeeplinkViewModel())
}
