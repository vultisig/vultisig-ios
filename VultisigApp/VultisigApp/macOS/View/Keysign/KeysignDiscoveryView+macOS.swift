//
//  KeysignDiscoveryView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-19.
//

#if os(macOS)
import SwiftUI

extension KeysignDiscoveryView {
    var container: some View {
        content
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
        .padding(.horizontal, 25)
    }
    
    var orientedContent: some View {
        landscapeContent
    }
    
    var qrCode: some View {
        qrCodeImage?
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: getMinSize(), maxHeight: getMinSize())
            .padding(32)
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
        .padding(.horizontal, 28)
        .edgesIgnoringSafeArea(.bottom)
        .padding(.bottom, 8)
    }
    
    var QRCodeContent: some View {
        VStack {
            paringQRCode
            disclaimer
        }
        .padding(60)
        .offset(y: -32)
    }
    
    var deviceList: some View {
        VStack {
            listTitle
            
            LazyVGrid(columns: columns, spacing: 18) {
                ThisDevicePeerCell(deviceName: "Mac")
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
    }
    
    var switchLink: some View {
        SwitchToLocalLink(selectedNetwork: $selectedNetwork)
            .padding(.bottom, 8)
    }
    
    func getMinSize() -> CGFloat {
        min(screenWidth/2, screenHeight/1.2)
    }
}
#endif
