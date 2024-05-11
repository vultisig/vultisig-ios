//
//  camera.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 10/05/24.
//
import Foundation
import AVFoundation
import CoreImage

class Camera: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var image: CIImage?
    @Published var isCameraAuthorized = false

    private var captureSession: AVCaptureSession?

    override init() {
        super.init()
        checkCameraAuthorization()
    }

    private func checkCameraAuthorization() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                isCameraAuthorized = true
                setUpAndStartCamera()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                    DispatchQueue.main.async {
                        self?.isCameraAuthorized = granted
                        if granted {
                            self?.setUpAndStartCamera()
                        } else {
                            self?.showCameraAccessDeniedAlert()
                        }
                    }
                }
            case .denied, .restricted:
                isCameraAuthorized = false
                showCameraAccessDeniedAlert()
            @unknown default:
                fatalError("Unknown camera authorization status")
        }
    }

    func setUpAndStartCamera() {
        guard isCameraAuthorized, let device = AVCaptureDevice.default(for: .video) else {
            print("Unable to access the camera")
            return
        }
        let captureSession = AVCaptureSession()
        captureSession.sessionPreset = .high

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }
            let videoOutput = AVCaptureVideoDataOutput()
            let queue = DispatchQueue(label: "cameraQueue", attributes: .concurrent)
            videoOutput.setSampleBufferDelegate(self, queue: queue)
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
            videoOutput.alwaysDiscardsLateVideoFrames = true
            if captureSession.canAddOutput(videoOutput) {
                captureSession.addOutput(videoOutput)
                configureVideoOrientation(for: videoOutput)
            }
            self.captureSession = captureSession
            self.captureSession?.startRunning()
        } catch {
            print("Error starting camera session:", error.localizedDescription)
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        DispatchQueue.main.async {
            self.image = ciImage
        }
    }

    private func configureVideoOrientation(for output: AVCaptureVideoDataOutput) {
        if let connection = output.connection(with: .video) {
            if #available(iOS 17.0, *) {
                connection.videoRotationAngle = .pi / 2 // 90 degrees rotation
            } else {
                connection.videoOrientation = .portrait
            }
        }
    }

    private func showCameraAccessDeniedAlert() {
        print("Please enable camera access in your system's privacy settings.")
    }
}
