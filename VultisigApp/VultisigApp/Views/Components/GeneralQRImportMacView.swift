//
//  KeygenQRImportMacView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-27.
//

import SwiftUI
import SwiftData

struct GeneralQRImportMacView: View {
    let vault: Vault
    let type: DeeplinkFlowType
    
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
        VStack {
            headerMac
            content
        }
    }
    
    var headerMac: some View {
        GeneralMacHeader(title: getTitle())
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
            JoinKeygenView(vault: vault)
        }
        .navigationDestination(isPresented: $shouldKeysignTransaction) {
            if let vault = homeViewModel.selectedVault {
                JoinKeysignView(vault: vault)
            }
        }
    }
    
    var title: some View {
        Text(getDescription())
            .font(.body16MontserratBold)
            .foregroundColor(.neutral0)
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
        Button {
            handleTap()
        } label: {
            FilledButton(title: "continue")
                .disabled(!isButtonEnabled)
                .grayscale(isButtonEnabled ? 0 : 1)
        }
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
        
        if type == .NewVault {
            text = "pair"
        } else {
            text = "keysign"
        }
        return NSLocalizedString(text, comment: "")
    }
    
    private func getDescription() -> String {
        let text: String
        
        if type == .NewVault {
            text = "uploadQRCodeImageKeygen"
        } else {
            text = "uploadQRCodeImageKeysign"
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
            presetValuesForDeeplink()
        } catch {
            if let description = error as? UtilsQrCodeFromImageError {
                alertDescription = description.localizedDescription
                showAlert = true
            }
            print(error)
        }
    }
    
    private func presetValuesForDeeplink() {
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
    GeneralQRImportMacView(vault: .example, type: .NewVault)
        .environmentObject(HomeViewModel())
        .environmentObject(DeeplinkViewModel())
}
