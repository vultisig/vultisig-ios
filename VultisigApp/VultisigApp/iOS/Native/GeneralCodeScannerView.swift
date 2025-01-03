//
//  GeneralCodeScannerView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-30.
//
#if os(iOS)
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import CodeScanner
import AVFoundation

struct GeneralCodeScannerView: View {
    @Binding var showSheet: Bool
    @Binding var shouldJoinKeygen: Bool
    @Binding var shouldKeysignTransaction: Bool
    @Binding var shouldSendCrypto: Bool
    @Binding var selectedChain: Chain?
    let sendTX: SendTransaction
    var showButtons: Bool = true
    
    @State var isGalleryPresented = false
    @State var isFilePresented = false
    
    @Query var vaults: [Vault]
    
    @EnvironmentObject var settingsDefaultChainViewModel: SettingsDefaultChainViewModel
    @EnvironmentObject var deeplinkViewModel: DeeplinkViewModel
    @EnvironmentObject var viewModel: HomeViewModel
    @EnvironmentObject var vaultDetailViewModel: VaultDetailViewModel
    
    var body: some View {
        ZStack {
            CodeScannerView(
                codeTypes: [.qr],
                isGalleryPresented: $isGalleryPresented,
                videoCaptureDevice: AVCaptureDevice.zoomedCameraForQRCode(withMinimumCodeSize: 100),
                completion: handleScan
            )
            
            overlay
            
            if showButtons {
                buttonsStack
            }
        }
        .ignoresSafeArea()
        .fileImporter(
            isPresented: $isFilePresented,
            allowedContentTypes: [UTType.image],
            allowsMultipleSelection: false
        ) { result in
            do {
                let qrCode = try Utils.handleQrCodeFromImage(result: result)
                let result = String(data: qrCode, encoding: .utf8)
                guard let url = URL(string: result ?? .empty) else {
                    return
                }
                
                deeplinkViewModel.extractParameters(url, vaults: vaults)
                presetValuesForDeeplink(url)
            } catch {
                print(error)
            }
        }
    }
    
    var overlay: some View {
        Image("QRScannerOutline")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .padding(60)
            .offset(y: -50)
            .allowsHitTesting(false)
    }
    
    var buttonsStack: some View {
        VStack {
            Spacer()
            buttons
        }
    }
    
    var buttons: some View {
        HStack(spacing: 0) {
            galleryButton
                .frame(maxWidth: .infinity)

            fileButton
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 50)
    }
    
    var galleryButton: some View {
        Button {
            isGalleryPresented.toggle()
        } label: {
            OpenButton(buttonIcon: "photo", buttonLabel: "uploadFromGallery")
        }
    }
    
    var fileButton: some View {
        Button {
            isFilePresented.toggle()
        } label: {
            OpenButton(buttonIcon: "folder", buttonLabel: "uploadFromFiles")
        }
    }
    
    private func handleScan(result: Result<ScanResult, ScanError>) {
        switch result {
        case .success(let result):
            guard let url = URL(string: result.string) else {
                return
            }
            deeplinkViewModel.extractParameters(url, vaults: vaults)
            presetValuesForDeeplink(url)
        case .failure(_):
            return
        }
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
            moveToSendView()
        }
    }
    
    private func moveToCreateVaultView() {
        shouldSendCrypto = false
        showSheet = false
        shouldJoinKeygen = true
    }
    
    private func moveToVaultsView() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            showSheet = false
            shouldSendCrypto = false
            shouldKeysignTransaction = true
        }
    }
    
    private func moveToSendView() {
        shouldJoinKeygen = false
        showSheet = false
        checkForAddress()
    }
    
    private func checkForAddress() {
        let address = deeplinkViewModel.address ?? ""
        sendTX.toAddress = address
        
        for asset in vaultDetailViewModel.groups {
            if checkForMAYAChain(asset: asset, address: address) {
                return
            }
            
            let isValid = asset.chain.coinType.validate(address: address)
            
            if isValid {
                selectedChain = asset.chain
                shouldSendCrypto = true
                return
            }
        }
        shouldSendCrypto = true
    }
    
    private func checkForMAYAChain(asset: GroupedChain, address: String) -> Bool {
        if asset.name.lowercased().contains("maya") && address.lowercased().contains("maya") {
            selectedChain = asset.chain
            shouldSendCrypto = true
            return true
        } else {
            return false
        }
    }
}

#Preview {
    GeneralCodeScannerView(
        showSheet: .constant(true),
        shouldJoinKeygen: .constant(true),
        shouldKeysignTransaction: .constant(true), 
        shouldSendCrypto: .constant(true),
        selectedChain: .constant(nil), 
        sendTX: SendTransaction()
    )
    .environmentObject(DeeplinkViewModel())
    .environmentObject(SettingsDefaultChainViewModel())
    .environmentObject(HomeViewModel())
    .environmentObject(VaultDetailViewModel())
}
#endif
