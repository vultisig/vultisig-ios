//
//  MacAddressScannerView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-01-16.
//

#if os(macOS)
import SwiftUI
import SwiftData
import AVFoundation

struct MacAddressScannerView: View {
    @Binding var address: String
    
    @StateObject var scannerViewModel = MacAddressScannerViewModel()
    
    var body: some View {
        ZStack(alignment: .top) {
            Background()
            main
            headerMac
        }
    }
    
    var main: some View {
        VStack(spacing: 0) {
            view
        }
        .onChange(of: scannerViewModel.detectedQRCode) { oldValue, newValue in
            scannerViewModel.handleScan()
        }
    }
    
    var headerMac: some View {
        GeneralMacHeader(title: "Scan")
            .padding(.bottom, 8)
    }
    
    var view: some View {
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
        NavigationLink {
            GeneralQRImportMacView(type: .SignTransaction)
        } label: {
            FilledButton(title: "uploadQRCodeImage")
        }
    }
    
    var tryAgainButton: some View {
        Button {
            scannerViewModel.setupSession()
        } label: {
            OutlineButton(title: "tryAgain")
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
}

#Preview {
    MacAddressScannerView(address: .constant(""))
}
#endif
