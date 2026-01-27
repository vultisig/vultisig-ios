//
//  MacCameraServiceViewModel+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-08-15.
//

#if os(macOS)
import AVFoundation
import AppKit
import SwiftUI

@MainActor
class MacCameraServiceViewModel: NSObject, ObservableObject {
    @Published var showCamera = false
    @Published var detectedQRCode: String?
    @Published var isCameraUnavailable = false
    @Published var showPlaceholderError = false

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
        // Parar sessão existente antes de criar nova
        if let existingSession = session, existingSession.isRunning {
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
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session?.canAddInput(input) == true {
                session?.addInput(input)
            }
        } catch {
            return
        }

        videoOutput = AVCaptureVideoDataOutput()
        videoOutput?.setSampleBufferDelegate(self, queue: outputQueue)

        if session?.canAddOutput(videoOutput!) == true {
            session?.addOutput(videoOutput!)
        }
    }

    func startSession() {
        guard let session = session else {
            return
        }

        if !session.isRunning {
            session.startRunning()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.showPlaceholderError = true
        }
    }

    func stopSession() {
        showPlaceholderError = false

        guard let session = session else {
            return
        }

        if session.isRunning {
            session.stopRunning()
        }
    }

    func getSession() -> AVCaptureSession? {
        return session
    }
}

extension MacCameraServiceViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    // swiftlint:disable:next unused_parameter
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

    func handleScan(vaults: [Vault], deeplinkViewModel: DeeplinkViewModel, error: Binding<Error?>) {
        guard let result = detectedQRCode, !result.isEmpty else {
            return
        }

        guard let url = URL(string: result) else {
            return
        }

        do {
            try deeplinkViewModel.extractParameters(url, vaults: vaults, isInternal: true)
        } catch let scanError {
            error.wrappedValue = scanError
        }
    }
}
#endif
