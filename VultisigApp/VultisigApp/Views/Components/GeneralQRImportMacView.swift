//
//  KeygenQRImportMacView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-27.
//

import SwiftUI
import SwiftData

struct GeneralQRImportMacView: View {
    let type: DeeplinkFlowType
    let sendTx: SendTransaction
    let selectedVault: Vault?
    
    @State var fileName: String? = nil
    @State var alertDescription = ""
    @State var importResult: Result<[URL], Error>? = nil
    
    @State var showAlert = false
    @State var isButtonEnabled = false
    @State var shouldJoinKeygen = false
    @State var shouldKeysignTransaction = false
    
#if os(iOS)
    @State var selectedImage: UIImage?
#elseif os(macOS)
    @State var selectedImage: NSImage?
#endif
    
    @Query var vaults: [Vault]
    
    @EnvironmentObject var homeViewModel: HomeViewModel
    @EnvironmentObject var deeplinkViewModel: DeeplinkViewModel
    
    var body: some View {
        ZStack {
            Background()
            main
        }
        .navigationBarBackButtonHidden(true)
    }
    
    var main: some View {
        content
            .crossPlatformToolbar(getTitle())
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
            JoinKeygenView(vault: Vault(name: "Main Vault"), selectedVault: selectedVault)
        }
        .navigationDestination(isPresented: $shouldKeysignTransaction) {
            if let vault = homeViewModel.selectedVault {
                JoinKeysignView(vault: vault)
            }
        }
    }
    
    var title: some View {
        Text(getDescription())
            .font(Theme.fonts.bodyMMedium)
            .foregroundColor(Theme.colors.textPrimary)
    }
    
    var uploadSection: some View {
        FileQRCodeImporterMac(
            fileName: fileName,
            resetData: resetData,
            handleFileImport: handleFileImport,
            selectedImage: selectedImage
        )
        .alert(isPresented: $showAlert) {
            alert
        }
    }
    
    var button: some View {
        PrimaryButton(title: "continue") {
            handleTap()
        }
        .disabled(!isButtonEnabled)
    }
    
    var alert: Alert {
        Alert(
            title: Text(NSLocalizedString("error", comment: "")),
            message: Text(NSLocalizedString(alertDescription, comment: "")),
            dismissButton: .default(Text(NSLocalizedString("ok", comment: "")))
        )
    }
    
    private func getTitle() -> String {
        let text: String
        
        switch type {
        case .NewVault:
            text = "pair"
        case .SignTransaction:
            text = "keysign"
        case .Unknown:
            text = "scanQRCode"
        }
        
        return NSLocalizedString(text, comment: "")
    }
    
    private func getDescription() -> String {
        let text: String
        
        switch type {
        case .NewVault:
            text = "uploadQRCodeImageKeygen"
        case .SignTransaction:
            text = "uploadQRCodeImageKeysign"
        case .Unknown:
            text = "uploadFileWithQRCode"
        }
        
        return NSLocalizedString(text, comment: "")
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
    
    private func handleTap() {
        guard let importResult else {
            return
        }
        
        do {
            let qrCode = try Utils.handleQrCodeFromImage(result: importResult)
            let result = String(data: qrCode, encoding: .utf8)
            
            guard let result, let url = URL(string: result) else {
                return
            }
            
            deeplinkViewModel.extractParameters(url, vaults: vaults)
            presetValuesForDeeplink(result)
        } catch {
            if let description = error as? UtilsQrCodeFromImageError {
                alertDescription = description.localizedDescription
                showAlert = true
            }
            print(error)
        }
    }
    
    private func presetValuesForDeeplink(_ result: String) {
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
            parseAddress(result)
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
    
    private func parseAddress(_ result: String) {
        sendTx.toAddress = result
    }
}

#Preview {
    GeneralQRImportMacView(type: .NewVault, sendTx: SendTransaction(), selectedVault: Vault.example)
        .environmentObject(HomeViewModel())
        .environmentObject(DeeplinkViewModel())
}
