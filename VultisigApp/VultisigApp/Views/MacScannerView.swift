//
//  MacScannerView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-08-15.
//

#if os(macOS)
import SwiftUI
import SwiftData
import AVFoundation

struct MacScannerView: View {
    let type: DeeplinkFlowType
    
    @Query var vaults: [Vault]
    
    @State var showAlert = false
    @State var alertDescription = ""
    @State var shouldJoinKeygen = false
    @State var shouldKeysignTransaction = false
    
    @EnvironmentObject var homeViewModel: HomeViewModel
    @EnvironmentObject var deeplinkViewModel: DeeplinkViewModel
    
    @StateObject private var macCameraServiceViewModel = MacCameraServiceViewModel()
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Background()
            main
        }
        .navigationBarBackButtonHidden(true)
        .navigationDestination(isPresented: $shouldJoinKeygen) {
            JoinKeygenView(vault: Vault(name: "Main Vault"))
        }
        .navigationDestination(isPresented: $shouldKeysignTransaction) {
            if let vault = homeViewModel.selectedVault {
                JoinKeysignView(vault: vault)
            }
        }
    }
    
    var main: some View {
        VStack(spacing: 0) {
            headerMac
            view
        }
        .alert(isPresented: $showAlert) {
            alert
        }
        .onChange(of: macCameraServiceViewModel.detectedQRCode) { oldValue, newValue in
            handleScan()
        }
    }
    
    var headerMac: some View {
        GeneralMacHeader(title: getTitle())
            .padding(.bottom, 8)
    }
    
    var view: some View {
        ZStack {
            if macCameraServiceViewModel.showPlaceholderError {
                errorView
            }
            
            if !macCameraServiceViewModel.showCamera {
                loader
            } else if macCameraServiceViewModel.isCameraUnavailable {
                errorView
            } else if let session = macCameraServiceViewModel.getSession() {
                getScanner(session)
            }
        }
    }
    
    var loader: some View {
        VStack {
            Spacer()
            
            HStack(spacing: 20) {
                Text(NSLocalizedString("initializingCamera", comment: ""))
                    .font(.body16MenloBold)
                    .foregroundColor(.neutral0)
                
                ProgressView()
                    .preferredColorScheme(.dark)
            }
            
            Spacer()
        }
    }
    
    var errorView: some View {
        VStack {
            Spacer()
            ErrorMessage(text: "noCameraFound")
            Spacer()
            buttons
        }
    }
    
    var buttons: some View {
        VStack(spacing: 20) {
            uploadQRCodeButton
            tryAgainButton
        }
        .padding(40)
    }
    
    var uploadQRCodeButton: some View {
        NavigationLink {
            GeneralQRImportMacView(type: type)
        } label: {
            FilledButton(title: "uploadQRCodeImage")
        }
    }
    
    var tryAgainButton: some View {
        Button {
            macCameraServiceViewModel.setupSession()
        } label: {
            OutlineButton(title: "tryAgain")
        }
    }
    
    var alert: Alert {
        Alert(
            title: Text(NSLocalizedString("error", comment: "")),
            message: Text(NSLocalizedString(alertDescription, comment: "")),
            dismissButton: .default(Text(NSLocalizedString("ok", comment: "")))
        )
    }
    
    private func getScanner(_ session: AVCaptureSession) -> some View {
        ZStack(alignment: .bottom) {
            MacCameraPreview(session: session)
                .onAppear {
                    macCameraServiceViewModel.startSession()
                }
                .onDisappear {
                    macCameraServiceViewModel.stopSession()
                }
            
            uploadQRCodeButton
                .padding(40)
        }
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
    
    private func handleScan() {
        guard let result = macCameraServiceViewModel.detectedQRCode, !result.isEmpty else {
            alertDescription = NSLocalizedString("errorFetchingValuesTryAgain", comment: "")
            showAlert = true
            return
        }
        
        guard let url = URL(string: result) else {
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
    MacScannerView(type: .NewVault)
        .environmentObject(HomeViewModel())
        .environmentObject(DeeplinkViewModel())
}
#endif
