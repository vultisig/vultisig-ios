//
//  MacScannerView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-08-15.
//

import SwiftUI
import AVFoundation

struct MacScannerView: View {
    let navigationTitle: String
    let type: DeeplinkFlowType
    
    @StateObject private var viewModel = MacCameraServiceViewModel()
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Background()
            main
        }
        .navigationBarBackButtonHidden(true)
    }
    
    var main: some View {
        VStack(spacing: 0) {
            headerMac
            view
        }
    }
    
    var headerMac: some View {
        GeneralMacHeader(title: navigationTitle)
            .padding(.bottom, 8)
    }
    
    var view: some View {
        ZStack {
            if viewModel.showPlaceholderError {
                errorView
            }
            
            if !viewModel.showCamera {
                loader
            } else if viewModel.isCameraUnavailable {
                errorView
            } else if let session = viewModel.getSession() {
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
    
    var buttons: some View {
        VStack(spacing: 20) {
            uploadQRCodeButton
            tryAgainButton
        }
        .padding(40)
    }
    
    var uploadQRCodeButton: some View {
        NavigationLink {
            GeneralQRImportMacView(type: type)
        } label: {
            FilledButton(title: "uploadQRCodeImage")
        }
    }
    
    var tryAgainButton: some View {
        Button {
            viewModel.setupSession()
        } label: {
            OutlineButton(title: "tryAgain")
        }
    }
    
    private func getScanner(_ session: AVCaptureSession) -> some View {
        ZStack(alignment: .bottom) {
            MacCameraPreview(session: session)
                .onAppear {
                    viewModel.startSession()
                }
                .onDisappear {
                    viewModel.stopSession()
                }
            
            uploadQRCodeButton
                .padding(40)
        }
    }
}

#Preview {
    MacScannerView(navigationTitle: "Scanner", type: .NewVault)
}
