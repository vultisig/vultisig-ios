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
        #if DEBUG
        print("🔍 MacCameraServiceViewModel.setupSession: Iniciando")
        #endif
        
        // Parar sessão existente antes de criar nova
        if let existingSession = session, existingSession.isRunning {
            #if DEBUG
            print("   Parando sessão existente antes de criar nova")
            #endif
            existingSession.stopRunning()
        }
        
        resetData()
        session = AVCaptureSession()
        session?.sessionPreset = .high
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.showCamera = true
        }
        
        guard let device = AVCaptureDevice.default(for: .video) else {
            isCameraUnavailable = true
            #if DEBUG
            print("   ❌ No video device found")
            #endif
            return
        }
        
        #if DEBUG
        print("   ✅ Camera device found: \(device.localizedName)")
        #endif
        
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session?.canAddInput(input) == true {
                session?.addInput(input)
                #if DEBUG
                print("   ✅ Input adicionado à sessão")
                #endif
            } else {
                #if DEBUG
                print("   ❌ Failed to add input to session")
                #endif
            }
        } catch {
            #if DEBUG
            print("   ❌ Failed to create device input: \(error)")
            #endif
            return
        }
        
        videoOutput = AVCaptureVideoDataOutput()
        videoOutput?.setSampleBufferDelegate(self, queue: outputQueue)
        
        if session?.canAddOutput(videoOutput!) == true {
            session?.addOutput(videoOutput!)
            #if DEBUG
            print("   ✅ Output adicionado à sessão")
            #endif
        } else {
            #if DEBUG
            print("   ❌ Failed to add output to session")
            #endif
        }
        
        #if DEBUG
        print("   ✅ setupSession concluído")
        #endif
    }
    
    func startSession() {
        #if DEBUG
        print("🔍 MacCameraServiceViewModel.startSession")
        print("   session existe: \(session != nil)")
        print("   session está rodando: \(session?.isRunning ?? false)")
        #endif
        
        guard let session = session else {
            #if DEBUG
            print("   ❌ Session é nil, não pode iniciar")
            #endif
            return
        }
        
        if !session.isRunning {
            session.startRunning()
            #if DEBUG
            print("   ✅ Sessão iniciada")
            #endif
        } else {
            #if DEBUG
            print("   ⚠️ Sessão já está rodando")
            #endif
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.showPlaceholderError = true
        }
    }
    
    func stopSession() {
        #if DEBUG
        print("🔍 MacCameraServiceViewModel.stopSession")
        print("   session existe: \(session != nil)")
        print("   session está rodando: \(session?.isRunning ?? false)")
        #endif
        
        showPlaceholderError = false
        
        guard let session = session else {
            #if DEBUG
            print("   ⚠️ Session é nil, nada para parar")
            #endif
            return
        }
        
        if session.isRunning {
            session.stopRunning()
            #if DEBUG
            print("   ✅ Sessão parada")
            #endif
        } else {
            #if DEBUG
            print("   ⚠️ Sessão já estava parada")
            #endif
        }
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
                let qrString = feature.messageString ?? ""
                #if DEBUG
                if !qrString.isEmpty && detectedQRCode != qrString {
                    print("🔍 MacCameraServiceViewModel: QR Code detectado na câmera!")
                    print("   QR Code: \(qrString.prefix(100))...")
                }
                #endif
                DispatchQueue.main.async {
                    self.detectedQRCode = qrString
                }
            }
        }
    }
}

// Deeplink
extension MacCameraServiceViewModel {
    func getTitle(_ type: DeeplinkFlowType) -> String {
        let text: String
        
        switch type {
        case .NewVault:
            text = "pair"
        case .SignTransaction:
            text = "keysign"
        case .Send, .Unknown:
            text = "scanQRCode"
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
        
        #if DEBUG
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔍 MacCameraServiceViewModel.handleScan")
        print("   QR Code detectado: \(result)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        #endif
        
        deeplinkViewModel.extractParameters(url, vaults: vaults)
        
        #if DEBUG
        print("   ✅ extractParameters chamado")
        print("   type agora é: \(String(describing: deeplinkViewModel.type))")
        #endif
        
        // Send notification immediately to process deeplink (extractParameters already sends it for .Send, but ensure it's sent)
        if deeplinkViewModel.type == .Send {
            #if DEBUG
            print("   📢 Type é .Send, enviando notificação ProcessDeeplink (backup)")
            #endif
            NotificationCenter.default.post(name: NSNotification.Name("ProcessDeeplink"), object: nil)
        }
        
        presetValuesForDeeplink(sendTx: sendTx, deeplinkViewModel: deeplinkViewModel, vaultDetailViewModel: vaultDetailViewModel, coinSelectionViewModel: coinSelectionViewModel)
    }
    
    func presetValuesForDeeplink(sendTx: SendTransaction, deeplinkViewModel: DeeplinkViewModel, vaultDetailViewModel: VaultDetailViewModel, coinSelectionViewModel: CoinSelectionViewModel) {
        #if DEBUG
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔍 MacCameraServiceViewModel.presetValuesForDeeplink")
        print("   type: \(String(describing: deeplinkViewModel.type))")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        #endif
        
        shouldJoinKeygen = false
        shouldKeysignTransaction = false
        
        guard let type = deeplinkViewModel.type else {
            #if DEBUG
            print("   ⚠️ type é nil, abortando")
            #endif
            return
        }
        
        #if DEBUG
        print("   ✅ type encontrado: \(type)")
        #endif
        
        deeplinkViewModel.type = nil
        
        switch type {
        case .NewVault:
            #if DEBUG
            print("   → Chamando moveToCreateVaultView()")
            #endif
            moveToCreateVaultView()
        case .SignTransaction:
            #if DEBUG
            print("   → Chamando moveToVaultsView()")
            #endif
            moveToVaultsView()
        case .Send, .Unknown:
            #if DEBUG
            print("   → Chamando moveToSendView()")
            #endif
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
                selectedChain = asset.chain
                
                // Just move to send - the chain will be added automatically by our new detection system
                self.stopSession()
                shouldSendCrypto = true
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
