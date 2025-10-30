//
//  MacAddressScannerView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-01-16.
//

import Foundation

struct AddressResult {
    let address: String
    let memo: String?
    let amount: String?
    
    init(address: String, memo: String? = nil, amount: String? = nil) {
        self.address = address
        self.memo = memo
        self.amount = amount
    }
    
    static func fromURI(_ uri: String) -> AddressResult? {
        guard URLComponents(string: uri) != nil else {
            print("Invalid URI")
            return nil
        }
        
        let (address, amount, message) = Utils.parseCryptoURI(uri)
        
        return AddressResult(address: address, memo: message, amount: amount)
    }
}

#if os(macOS)
import SwiftUI
import SwiftData
import AVFoundation

struct MacAddressScannerView: View {
    @Binding var showCameraScanView: Bool
    let selectedVault: Vault?
    var onParsedResult: (AddressResult?) -> Void
    
    @State var showImportOptions: Bool = false
    
    @StateObject var scannerViewModel = MacAddressScannerViewModel()
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack(alignment: .top) {
            Background()
            content
        }
        .crossPlatformToolbar("scanQRCode".localized, ignoresTopEdge: true)
        .onChange(of: scannerViewModel.detectedQRCode) { oldValue, newValue in
            handleScan()
        }
    }
    
    var content: some View {
        ZStack {
            if showImportOptions {
                importOption
            } else {
                camera
            }
        }
    }
    
    var importOption: some View {
        GeneralQRImportMacView(type: .Unknown, selectedVault: selectedVault) { address in
            goBack()
            onParsedResult(AddressResult(address: address))
        }
    }
    
    var camera: some View {
        ZStack {
            if scannerViewModel.showPlaceholderError {
                fallbackErrorView
            }
            
            if !scannerViewModel.showCamera {
                loader
            } else if scannerViewModel.isCameraUnavailable {
                errorView
            } else if let session = scannerViewModel.getSession() {
                getScanner(session)
            }
        }
    }
    
    var loader: some View {
        VStack {
            Spacer()
            
            HStack(spacing: 20) {
                Text(NSLocalizedString("initializingCamera", comment: ""))
                    .font(Theme.fonts.bodyMMedium)
                    .foregroundColor(Theme.colors.textPrimary)
                
                ProgressView()
                    .preferredColorScheme(.dark)
            }
            
            Spacer()
        }
    }
    
    var errorView: some View {
        VStack {
            Spacer()
            ErrorMessage(text: "noCameraFound")
            Spacer()
            buttons
        }
    }
    
    var fallbackErrorView: some View {
        VStack {
            Spacer()
            ErrorMessage(text: "noCameraFound")
            Spacer()
        }
    }
    
    var buttons: some View {
        VStack(spacing: 20) {
            uploadQRCodeButton
            tryAgainButton
        }
        .padding(40)
    }
    
    var uploadQRCodeButton: some View {
        PrimaryButton(title: "uploadQRCodeImage") {
            showImportOptions = true
        }
    }
    
    var tryAgainButton: some View {
        PrimaryButton(title: "tryAgain", type: .secondary) {
            scannerViewModel.setupSession()
        }
    }
    
    private func getScanner(_ session: AVCaptureSession) -> some View {
        ZStack(alignment: .bottom) {
            MacCameraPreview(session: session)
                .onAppear {
                    scannerViewModel.startSession()
                }
                .onDisappear {
                    scannerViewModel.stopSession()
                }
            
            uploadQRCodeButton
                .padding(40)
        }
    }
    
    private func handleScan() {
        guard let detectedQRCode = scannerViewModel.detectedQRCode else {
            return
        }
        
        goBack()
        onParsedResult(AddressResult.fromURI(detectedQRCode))
    }
    
    private func goBack() {
        scannerViewModel.stopSession()
        showImportOptions = false
        showCameraScanView = false
        dismiss()
    }
}

#Preview {
    MacAddressScannerView(
        showCameraScanView: .constant(true),
        selectedVault: Vault.example
    ) { _ in }
}
#endif
