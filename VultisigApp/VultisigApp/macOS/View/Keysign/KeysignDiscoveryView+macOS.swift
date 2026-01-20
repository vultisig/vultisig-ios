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
    
    var background: some View {
        GeometryReader { proxy in
            Background()
                .onAppear {
                    setSize(proxy)
                }
                .onChange(of: proxy.size) { oldValue, newValue in
                    setSize(proxy)
                }
        }
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
        portraitContent
    }
    
    var qrCode: some View {
        qrCodeImage?
            .resizable()
            .padding(32)
            .frame(width: getMinSize(), height: getMinSize())
    }
    
    var deviceList: some View {
        VStack {
            listTitle
            
            LazyVGrid(columns: adaptiveColumnsMac, spacing: 18) {
                ThisDevicePeerCell(deviceName: "Mac")
                devices
                EmptyPeerCell()
            }
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
        SwitchToLocalLink(isForKeygen: false, selectedNetwork: $selectedNetwork)
            .padding(.bottom, 24)
    }
    
    func getMinSize() -> CGFloat {
        min(screenWidth/2.3, screenHeight/1.2)
    }
    
    private func setSize(_ proxy: GeometryProxy) {
        screenWidth = proxy.size.width
        screenHeight = proxy.size.height
    }
}
#endif
