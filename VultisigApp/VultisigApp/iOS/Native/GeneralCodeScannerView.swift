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
    
    @State var showAlert: Bool = false
    @State var newCoinMeta: CoinMeta? = nil
    
    @EnvironmentObject var settingsDefaultChainViewModel: SettingsDefaultChainViewModel
    @EnvironmentObject var deeplinkViewModel: DeeplinkViewModel
    @EnvironmentObject var viewModel: HomeViewModel
    @EnvironmentObject var vaultDetailViewModel: VaultDetailViewModel
    @EnvironmentObject var coinSelectionViewModel: CoinSelectionViewModel
    @EnvironmentObject var homeViewModel: HomeViewModel
    
    private var idiom : UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
    
    var body: some View {
        ZStack {
            cameraView
            content
        }
        .frame(maxWidth: idiom == .pad ? .infinity : nil, maxHeight: idiom == .pad ? .infinity : nil)
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
        .alert(isPresented: $showAlert) {
            alert
        }
        .overlay {
            background
        }
    }
    
    var background: some View {
        Image("QRScannerBackgroundImage")
            .resizable()
            .scaledToFill()
            .opacity(0.2)
    }
    
    var content: some View {
        VStack {
            header
            Spacer()
            if showButtons {
                buttons
            }
        }
        .padding(.vertical, 8)
    }
    
    var header: some View {
        HStack {
            backButton
            Spacer()
            title
            Spacer()
            helpButton
        }
        .foregroundColor(.neutral0)
        .font(.body18BrockmannMedium)
        .padding(16)
        .offset(y: 8)
    }
    
    var backButton: some View {
        Button {
            showSheet = false
        } label: {
            getIcon(for: "xmark")
        }
    }
    
    var title: some View {
        Text(NSLocalizedString("scanQRStartScreen", comment: ""))
    }
    
    var helpButton: some View {
        Link(destination: URL(string: Endpoint.supportDocumentLink)!) {
            getIcon(for: "questionmark.circle")
        }
    }
    
    var cameraView: some View {
        ZStack {
            CodeScannerView(
                codeTypes: [.qr],
                isGalleryPresented: $isGalleryPresented,
                videoCaptureDevice: AVCaptureDevice.zoomedCameraForQRCode(withMinimumCodeSize: 100),
                completion: handleScan
            )
            
            overlay
        }
    }
    
    var border: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(Color.neutral0, lineWidth: 1)
            .opacity(0.2)
    }
    
    var overlay: some View {
        Image("QRScannerOutline")
            .padding(60)
            .allowsHitTesting(false)
    }
    
    var buttons: some View {
        VStack {
            galleryButton
            fileButton
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 30)
    }
    
    var galleryButton: some View {
        Button {
            isGalleryPresented.toggle()
        } label: {
            FilledButton(title: "uploadFromGallerySingleLine")
        }
    }
    
    var fileButton: some View {
        Button {
            isFilePresented.toggle()
        } label: {
            FilledButton(title: "uploadFromFilesSingleLine")
        }
    }
    
    var alert: Alert {
        let message = NSLocalizedString("addNewChainToVault1", comment: "") + (newCoinMeta?.chain.name ?? "") + NSLocalizedString("addNewChainToVault2", comment: "")
        
        return Alert(
            title: Text(NSLocalizedString("newChainDetected", comment: "")),
            message: Text(message),
            primaryButton: Alert.Button.default(
                Text(NSLocalizedString("addChain", comment: "")),
                action: {
                    addNewChain()
                }
            ),
            secondaryButton: Alert.Button.default(
                Text(NSLocalizedString("cancel", comment: "")),
                action: {
                    handleCancel()
                }
            )
        )
    }
    
    private func getIcon(for icon: String) -> some View {
        Image(systemName: icon)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            shouldJoinKeygen = false
            showSheet = false
            checkForAddress()
        }
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
        
        checkForRemainingChains(address)
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
    
    private func checkForRemainingChains(_ address: String) {
        showSheet = true
        
        let chains = coinSelectionViewModel.groupedAssets.values.flatMap { $0 }
        
        for asset in chains.sorted(by: {
            $0.chain.name < $1.chain.name
        }) {
            let isValid = asset.coinType.validate(address: address)
            
            if isValid {
                newCoinMeta = asset
                showAlert = true
                return
            }
        }
    }
    
    private func handleCancel() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            showSheet = false
            shouldSendCrypto = true
        }
    }
    
    private func addNewChain() {
        guard let chain = newCoinMeta else {
            return
        }
        
        selectedChain = chain.chain
        saveAssets(chain)
    }
    
    private func saveAssets(_ chain: CoinMeta) {
        var selection = coinSelectionViewModel.selection
        selection.insert(chain)
        
        guard let vault = homeViewModel.selectedVault else {
            return
        }
        
        Task{
            await CoinService.saveAssets(for: vault, selection: selection)
            
            handleCancel()
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
    .environmentObject(CoinSelectionViewModel())
    .environmentObject(HomeViewModel())
}
#endif
