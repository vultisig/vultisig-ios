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
    let sendTx: SendTransaction
    
    @Query var vaults: [Vault]
    
    @State var selectedChain: Chain? = nil
    @State var shouldSendCrypto = false
    @State var shouldJoinKeygen = false
    @State var shouldKeysignTransaction = false
    
    @EnvironmentObject var homeViewModel: HomeViewModel
    @EnvironmentObject var deeplinkViewModel: DeeplinkViewModel
    @EnvironmentObject var macCameraServiceViewModel: MacCameraServiceViewModel
    @EnvironmentObject var settingsDefaultChainViewModel: SettingsDefaultChainViewModel
    
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
        .navigationDestination(isPresented: $shouldSendCrypto) {
            if let vault = homeViewModel.selectedVault {
                SendCryptoView(
                    tx: sendTx,
                    vault: vault,
                    selectedChain: selectedChain
                )
            }
        }
    }
    
    var main: some View {
        VStack(spacing: 0) {
            headerMac
            view
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
            moveToCreateVaultView()
        case .SignTransaction:
            moveToVaultsView()
        case .Unknown:
            moveToSendView()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            macCameraServiceViewModel.detectedQRCode = ""
        }
    }
    
    private func moveToCreateVaultView() {
        shouldSendCrypto = false
        shouldKeysignTransaction = false
        shouldJoinKeygen = true
    }
    
    private func moveToVaultsView() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            shouldJoinKeygen = false
            shouldSendCrypto = false
            shouldKeysignTransaction = true
        }
    }
    
    private func moveToSendView() {
        shouldJoinKeygen = false
        shouldKeysignTransaction = false
        checkForAddress()
    }
    
    private func checkForAddress() {
        let address = deeplinkViewModel.address ?? ""
        sendTx.toAddress = address
        
        let sortedAssets = settingsDefaultChainViewModel.baseChains.sorted(by: {
            $0.chain.name > $1.chain.name
        })
        
        for asset in sortedAssets {
            let isValid = asset.chain.coinType.validate(address: address)
            
            if isValid {
                selectedChain = asset.chain
                shouldSendCrypto = true
                return
            }
        }
        shouldSendCrypto = true
    }
}

#Preview {
    MacScannerView(type: .NewVault, sendTx: SendTransaction())
        .environmentObject(HomeViewModel())
        .environmentObject(DeeplinkViewModel())
        .environmentObject(MacCameraServiceViewModel())
        .environmentObject(SettingsDefaultChainViewModel())
}
#endif
