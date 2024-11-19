//
//  KeysignDiscoveryView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-19.
//

#if os(iOS)
import SwiftUI

extension KeysignDiscoveryView {
    private var idiom : UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
    
    var container: some View {
        content
            .detectOrientation($orientation)
    }
    
    var view: some View {
        VStack {
            switch viewModel.status {
            case .WaitingForDevices:
                waitingForDevices
            case .WaitingForFast:
                lookingForDevices
            case .FailToStart:
                errorText
            }
        }
        .blur(radius: isLoading ? 1 : 0)
    }
    
    var orientedContent: some View {
        ZStack {
            if orientation == .landscapeLeft || orientation == .landscapeRight {
                landscapeContent
            } else {
                portraitContent
            }
        }
    }
    
    var list: some View {
        VStack(spacing: 4) {
            if participantDiscovery.peersFound.count == 0 {
                lookingForDevices
            } else {
                deviceList
            }
        }
    }
    
    var paringQRCode: some View {
        VStack {
            networkPrompts
            qrCode
        }
        .foregroundColor(.neutral0)
        .cornerRadius(10)
    }
    
    var qrCode: some View {
        ZStack {
            qrCodeImage?
                .resizable()
                .frame(width: getQRSize())
                .frame(height: getQRSize())
                .scaledToFit()
                .padding(2)
                .background(Color.neutral0)
                .cornerRadius(10)
                .padding(4)
                .padding(12)
                .background(Color.blue600)
                .cornerRadius(30)
                .padding(1)
            
            Image("QRScannerOutline")
                .resizable()
                .frame(width: getQROutline(), height: getQROutline())
        }
    }
    
    var bottomButtons: some View {
        let isDisabled = viewModel.selections.count < (vault.getThreshold() + 1)
        
        return Button {
            isLoading = true
            startKeysign()
        } label: {
            FilledButton(title: "sign")
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.8 : 1)
        .grayscale(isDisabled ? 1 : 0)
        .padding(.horizontal, 16)
        .background(Color.backgroundBlue.opacity(0.95))
        .edgesIgnoringSafeArea(.bottom)
        .padding(.bottom, idiom == .pad ? 30 : 0)
    }
    
    var deviceList: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 24) {
                ForEach(participantDiscovery.peersFound, id: \.self) { peer in
                    Button {
                        handleSelection(peer)
                    } label: {
                        PeerCell(id: peer, isSelected: viewModel.selections.contains(peer))
                    }
                    .onAppear {
                        if participantDiscovery.peersFound.count == 1 && participantDiscovery.peersFound.first == peer {
                            handleSelection(peer)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .frame(maxHeight: .infinity)
        }
    }
    
    private func getQRSize() -> CGFloat {
        guard !isPhoneSE else {
            return 250
        }
        
        guard idiom == .phone else {
            return screenWidth-335
        }
        
        return screenWidth-80
    }
    
    private func getQROutline() -> CGFloat {
        guard !isPhoneSE else {
            return 280
        }
        
        guard idiom == .phone else {
            return screenWidth-300
        }
        
        return screenWidth-45
    }
}
#endif
