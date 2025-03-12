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
    
    var list: some View {
        deviceList
    }
    
    var qrCode: some View {
        qrCodeImage?
            .resizable()
            .scaledToFit()
            .padding(18)
            .background(Color.clear)
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
        .padding(.horizontal, 28)
        .edgesIgnoringSafeArea(.bottom)
        .padding(.bottom, 8)
    }
    
    var deviceList: some View {
        VStack {
            listTitle
            
            ScrollView {
                LazyVGrid(columns: phoneColumns, spacing: 18) {
                    ThisDevicePeerCell(deviceName: "Mac")
                    devices
                    EmptyPeerCell(counter: participantDiscovery.peersFound.count)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 120)
            }
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
            .padding(.bottom, 40)
    }
    
    var paringQRCode: some View {
        ZStack {
            animation
            qrCode
        }
        .padding(48)
        .foregroundColor(.neutral0)
    }
}
#endif
