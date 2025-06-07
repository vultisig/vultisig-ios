//
//  MacCameraServiceViewModel+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-08-15.
//

#if os(macOS)
import AVFoundation
import AppKit

@MainActor
class MacCameraServiceViewModel: NSObject, ObservableObject {
    @Published var showCamera = false
    @Published var detectedQRCode: String?
    @Published var isCameraUnavailable = false
    @Published var showPlaceholderError = false
    
    @Published var selectedChain: Chain? = nil
    @Published var shouldSendCrypto = false
    @Published var shouldJoinKeygen = false
    @Published var shouldKeysignTransaction = false
    
    @Published var showAlert: Bool = false
    @Published var newCoinMeta: CoinMeta? = nil
    
    private var session: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var outputQueue = DispatchQueue(label: "CameraOutputQueue")
    
    override init() {
        super.init()
        setupSession()
    }
    
    func resetData() {
        showCamera = false
        detectedQRCode = nil
        isCameraUnavailable = false
        session = nil
        videoOutput = nil
        showPlaceholderError = false
    }
    
    func setupSession() {
        resetData()
        session = AVCaptureSession()
        session?.sessionPreset = .high
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.showCamera = true
        }
        
        guard let device = AVCaptureDevice.default(for: .video) else {
            isCameraUnavailable = true
            print("No video device found")
            return
        }
        
        print("Camera device found: \(device.localizedName)")
        
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session?.canAddInput(input) == true {
                session?.addInput(input)
            } else {
                print("Failed to add input to session")
            }
        } catch {
            print("Failed to create device input: \(error)")
            return
        }
        
        videoOutput = AVCaptureVideoDataOutput()
        videoOutput?.setSampleBufferDelegate(self, queue: outputQueue)
        
        if session?.canAddOutput(videoOutput!) == true {
            session?.addOutput(videoOutput!)
        } else {
            print("Failed to add output to session")
        }
    }
    
    func startSession() {
        session?.startRunning()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.showPlaceholderError = true
        }
    }
    
    func stopSession() {
        showPlaceholderError = false
        session?.stopRunning()
    }
    
    func getSession() -> AVCaptureSession? {
        return session
    }
}

extension MacCameraServiceViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        detectQRCode(in: ciImage)
    }
    
    private func detectQRCode(in image: CIImage) {
        let context = CIContext()
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: context, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        
        if let features = detector?.features(in: image) as? [CIQRCodeFeature] {
            for feature in features {
                DispatchQueue.main.async {
                    self.detectedQRCode = feature.messageString
                }
            }
        }
    }
}

// Deeplink
extension MacCameraServiceViewModel {
    func getTitle(_ type: DeeplinkFlowType) -> String {
        let text: String
        
        if type == .NewVault {
            text = "pair"
        } else {
            text = "keysign"
        }
        return NSLocalizedString(text, comment: "")
    }
    
    func handleScan(vaults: [Vault], sendTx: SendTransaction, deeplinkViewModel: DeeplinkViewModel, vaultDetailViewModel: VaultDetailViewModel, coinSelectionViewModel: CoinSelectionViewModel) {
        guard let result = detectedQRCode, !result.isEmpty else {
            return
        }
        
        guard let url = URL(string: result) else {
            return
        }
        
        deeplinkViewModel.extractParameters(url, vaults: vaults)
        presetValuesForDeeplink(sendTx: sendTx, deeplinkViewModel: deeplinkViewModel, vaultDetailViewModel: vaultDetailViewModel, coinSelectionViewModel: coinSelectionViewModel)
    }
    
    func presetValuesForDeeplink(sendTx: SendTransaction, deeplinkViewModel: DeeplinkViewModel, vaultDetailViewModel: VaultDetailViewModel, coinSelectionViewModel: CoinSelectionViewModel) {
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
            moveToSendView(sendTx: sendTx, deeplinkViewModel: deeplinkViewModel, vaultDetailViewModel: vaultDetailViewModel, coinSelectionViewModel: coinSelectionViewModel)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
            detectedQRCode = ""
        }
    }
    
    private func moveToCreateVaultView() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.shouldSendCrypto = false
            self.shouldKeysignTransaction = false
            self.stopSession()
            self.shouldJoinKeygen = true
        }
    }
    
    private func moveToVaultsView() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.shouldJoinKeygen = false
            self.shouldSendCrypto = false
            self.stopSession()
            self.shouldKeysignTransaction = true
        }
    }
    
    private func moveToSendView(sendTx: SendTransaction, deeplinkViewModel: DeeplinkViewModel, vaultDetailViewModel: VaultDetailViewModel, coinSelectionViewModel: CoinSelectionViewModel) {
        shouldJoinKeygen = false
        shouldKeysignTransaction = false
        checkForAddress(sendTx: sendTx, deeplinkViewModel: deeplinkViewModel, vaultDetailViewModel: vaultDetailViewModel, coinSelectionViewModel: coinSelectionViewModel)
    }
    
    private func checkForAddress(sendTx: SendTransaction, deeplinkViewModel: DeeplinkViewModel, vaultDetailViewModel: VaultDetailViewModel, coinSelectionViewModel: CoinSelectionViewModel) {
        let address = deeplinkViewModel.address ?? ""
        sendTx.toAddress = address
        
        let sortedAssets = vaultDetailViewModel.groups
        
        for asset in sortedAssets {
            if checkForMAYAChain(asset: asset.chain, address: address) {
                return
            }
            
            let isValid = asset.chain.coinType.validate(address: address)
            
            if isValid {
                selectedChain = asset.chain
                self.stopSession()
                shouldSendCrypto = true
                return
            }
        }
        
        checkForRemainingChains(address: address, coinSelectionViewModel: coinSelectionViewModel)
    }
    
    private func checkForMAYAChain(asset: Chain, address: String) -> Bool {
        if asset.name.lowercased().contains("maya") && address.lowercased().contains("maya") {
            selectedChain = asset
            self.stopSession()
            shouldSendCrypto = true
            return true
        } else {
            return false
        }
    }
    
    private func checkForRemainingChains(address: String, coinSelectionViewModel: CoinSelectionViewModel) {
        showCamera = true
        
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
    
    func handleCancel() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.showCamera = false
            self.stopSession()
            self.shouldSendCrypto = true
        }
    }
    
    func addNewChain(coinSelectionViewModel: CoinSelectionViewModel, homeViewModel: HomeViewModel) {
        guard let chain = newCoinMeta else {
            return
        }
        
        selectedChain = chain.chain
        saveAssets(chain: chain, coinSelectionViewModel: coinSelectionViewModel, homeViewModel: homeViewModel)
    }
    
    private func saveAssets(chain: CoinMeta, coinSelectionViewModel: CoinSelectionViewModel, homeViewModel: HomeViewModel) {
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
#endif
