//
//  MacAddressScannerViewModel+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-01-16.
//

#if os(macOS)
import SwiftUI
import AVFoundation
import AppKit

@MainActor
class MacAddressScannerViewModel: NSObject, ObservableObject {
    @Published var showAlert = false
    @Published var showCamera = false
    @Published var detectedQRCode: String?
    @Published var isCameraUnavailable = false
    @Published var showPlaceholderError = false

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

extension MacAddressScannerViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {
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
                DispatchQueue.main.async {
                    self.detectedQRCode = feature.messageString
                }
            }
        }
    }
}
#endif
