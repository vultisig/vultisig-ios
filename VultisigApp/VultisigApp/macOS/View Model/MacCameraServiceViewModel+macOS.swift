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
    
    func handleScan(vaults: [Vault], sendTx: SendTransaction, cameraViewModel: MacCameraServiceViewModel, deeplinkViewModel: DeeplinkViewModel, settingsDefaultChainViewModel: SettingsDefaultChainViewModel) {
        guard let result = cameraViewModel.detectedQRCode, !result.isEmpty else {
            return
        }
        
        guard let url = URL(string: result) else {
            return
        }
        
        deeplinkViewModel.extractParameters(url, vaults: vaults)
        presetValuesForDeeplink(sendTx: sendTx, cameraViewModel: cameraViewModel, deeplinkViewModel: deeplinkViewModel, settingsDefaultChainViewModel: settingsDefaultChainViewModel)
    }
    
    func presetValuesForDeeplink(sendTx: SendTransaction, cameraViewModel: MacCameraServiceViewModel, deeplinkViewModel: DeeplinkViewModel, settingsDefaultChainViewModel: SettingsDefaultChainViewModel) {
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
            moveToSendView(sendTx: sendTx, deeplinkViewModel: deeplinkViewModel, settingsDefaultChainViewModel: settingsDefaultChainViewModel)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            cameraViewModel.detectedQRCode = ""
        }
    }
    
    private func moveToCreateVaultView() {
        shouldSendCrypto = false
        shouldKeysignTransaction = false
        shouldJoinKeygen = true
    }
    
    private func moveToVaultsView() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.shouldJoinKeygen = false
            self.shouldSendCrypto = false
            self.shouldKeysignTransaction = true
        }
    }
    
    private func moveToSendView(sendTx: SendTransaction, deeplinkViewModel: DeeplinkViewModel, settingsDefaultChainViewModel: SettingsDefaultChainViewModel) {
        shouldJoinKeygen = false
        shouldKeysignTransaction = false
        checkForAddress(sendTx: sendTx, deeplinkViewModel: deeplinkViewModel, settingsDefaultChainViewModel: settingsDefaultChainViewModel)
    }
    
    private func checkForAddress(sendTx: SendTransaction, deeplinkViewModel: DeeplinkViewModel, settingsDefaultChainViewModel: SettingsDefaultChainViewModel) {
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
#endif
