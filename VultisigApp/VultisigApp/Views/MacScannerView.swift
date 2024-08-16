//
//  MacScannerView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-08-15.
//

import SwiftUI

struct MacScannerView: View {
    let navigationTitle: String
    
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
                MacCameraPreview(session: session)
                    .onAppear {
                        viewModel.startSession()
                    }
                    .onDisappear {
                        viewModel.stopSession()
                    }
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
            button
        }
    }
    
    var button: some View {
        Button {
            viewModel.setupSession()
        } label: {
            FilledButton(title: "tryAgain")
        }
        .padding(40)
    }
}

#Preview {
    MacScannerView(navigationTitle: "Scanner")
}
