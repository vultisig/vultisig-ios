//
//  ApplicationState.swift
//  VultisigApp
//

import SwiftUI
import AVFoundation

final class ApplicationState: ObservableObject {
    @Published var isCameraPermissionGranted: Bool = false
    
    // Singleton
    static let shared = ApplicationState()
    
    init() {}
    
    func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            DispatchQueue.main.async {
                self.isCameraPermissionGranted = true
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    self.isCameraPermissionGranted = granted
                }
            }
        case .denied, .restricted:
            DispatchQueue.main.async {
                self.isCameraPermissionGranted = false
            }
        @unknown default:
            DispatchQueue.main.async {
                self.isCameraPermissionGranted = false
            }
        }
    }
}
