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
        VStack(spacing: 18) {
            if participantDiscovery.peersFound.count == 0 {
                lookingForDevices
            } else {
                deviceList
            }
        }
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
        ScrollView {
            LazyVGrid(columns: columns, spacing: 32) {
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
