//
//  MacCameraService.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-08-15.
//

import AVFoundation
import AppKit

class MacCameraService: NSObject, ObservableObject {
    @Published var detectedQRCode: String?
    
    private var session: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var outputQueue = DispatchQueue(label: "CameraOutputQueue")
    
    override init() {
        super.init()
        setupSession()
    }
    
    private func setupSession() {
        session = AVCaptureSession()
        session?.sessionPreset = .high
        
        // Check if the camera device is available
        guard let device = AVCaptureDevice.default(for: .video) else {
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
    }
    
    func stopSession() {
        session?.stopRunning()
    }
    
    func getSession() -> AVCaptureSession? {
        return session
    }
}

extension MacCameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
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
