//
//  MacAddressScannerView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-01-16.
//

#if os(macOS)
import SwiftUI
import SwiftData
import AVFoundation

struct MacAddressScannerView: View {
    @ObservedObject var tx: SendTransaction
    @ObservedObject var sendCryptoViewModel: SendCryptoViewModel
    @Binding var showCameraScanView: Bool
    let selectedVault: Vault?
    
    @State var showImportOptions: Bool = false
    
    @StateObject var scannerViewModel = MacAddressScannerViewModel()
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack(alignment: .top) {
            Background()
            content
            headerMac
        }
        .onChange(of: scannerViewModel.detectedQRCode) { oldValue, newValue in
            handleScan()
        }
        .onChange(of: tx.toAddress) { oldValue, newValue in
            goBack()
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
        GeneralQRImportMacView(type: .Unknown, sendTx: tx, selectedVault: selectedVault)
    }
    
    var headerMac: some View {
        GeneralMacHeader(title: "scanQRCode")
            .padding(.bottom, 8)
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
                    .font(.body16MenloBold)
                    .foregroundColor(.neutral0)
                
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
        VultiButton(title: "uploadQRCodeImage") {
            showImportOptions = true
        }
    }
    
    var tryAgainButton: some View {
        VultiButton(title: "tryAgain", type: .secondary) {
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
        
        tx.parseCryptoURI(detectedQRCode)
        validateAddress(tx.toAddress)
        goBack()
    }
    
    private func goBack() {
        scannerViewModel.stopSession()
        showImportOptions = false
        showCameraScanView = false
        dismiss()
    }
    
    func validateAddress(_ newValue: String) {
        sendCryptoViewModel.validateAddress(tx: tx, address: newValue)
    }
}

#Preview {
    MacAddressScannerView(
        tx: SendTransaction(),
        sendCryptoViewModel: SendCryptoViewModel(),
        showCameraScanView: .constant(true),
        selectedVault: Vault.example
    )
}
#endif
