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
            .frame(maxWidth: isPhoneSE ? 250 : nil)
            .frame(maxHeight: isPhoneSE ? 250 : nil)
            .scaledToFit()
            .padding(2)
            .cornerRadius(10)
            .padding(16)
            .background(Color.blue600)
            .cornerRadius(20)
            .overlay (
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Color.turquoise600, style: StrokeStyle(lineWidth: 2, dash: [52]))
            )
            .padding(1)
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
        .padding(.horizontal, 40)
        .background(Color.backgroundBlue.opacity(0.95))
        .edgesIgnoringSafeArea(.bottom)
        .padding(.bottom, 40)
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
}
#endif
