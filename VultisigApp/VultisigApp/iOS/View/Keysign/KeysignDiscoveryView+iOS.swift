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
    
    var background: some View {
        Background()
    }
    
    var orientedContent: some View {
        portraitContent
    }
    
    var QRCodeContent: some View {
        VStack {
            paringQRCode
            disclaimer
        }
    }
    
    var qrCode: some View {
        qrCodeImage?
            .resizable()
            .frame(maxWidth: 500, maxHeight: 500)
            .aspectRatio(contentMode: .fill)
            .padding(24)
    }
    
    var signButton: some View {
        let isDisabled = viewModel.selections.count < (vault.getThreshold() + 1)
        
        return Button(action: {
            isLoading = true
            startKeysign()
        }) {
            FilledButton(
                title: isDisabled ? "waitingOnDevices..." : "sign",
                textColor: isDisabled ? .textDisabled : .blue600,
                background: isDisabled ? .buttonDisabled : .turquoise600
            )
        }
        .disabled(isDisabled)
        .padding(.horizontal, 32)
        .edgesIgnoringSafeArea(.bottom)
        .padding(2)
    }
    
    var deviceList: some View {
        VStack {
            listTitle
            
            LazyVGrid(columns: adaptiveColumns, spacing: 18) {
                ThisDevicePeerCell(deviceName: idiom == .phone ? "iPhone" : "iPad")
                devices
                EmptyPeerCell(counter: participantDiscovery.peersFound.count)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 120)
        }
    }
    
    var devices: some View {
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
        .padding(idiom == .phone ? 0 : 8)
    }
    
    var switchLink: some View {
        SwitchToLocalLink(selectedNetwork: $selectedNetwork)
    }
}
#endif
