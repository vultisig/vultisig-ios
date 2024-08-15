//
//  MacScannerView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-08-15.
//

import SwiftUI

struct MacScannerView: View {
    let navigationTitle: String
    
    @StateObject private var cameraService = MacCameraService()
    
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
    }
    
    var view: some View {
        ZStack {
            if let session = cameraService.getSession() {
                MacCameraPreview(session: session)
                    .onAppear {
                        cameraService.startSession()
                    }
                    .onDisappear {
                        cameraService.stopSession()
                    }
            }
        }
    }
}

#Preview {
    MacScannerView(navigationTitle: "Scanner")
}
