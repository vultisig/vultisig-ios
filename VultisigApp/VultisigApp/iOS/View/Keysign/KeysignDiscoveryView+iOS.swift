//
//  KeysignDiscoveryView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-19.
//

#if os(iOS)
import SwiftUI

extension KeysignDiscoveryView {
    private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }

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

    var deviceList: some View {
        VStack {
            listTitle

            LazyVGrid(columns: adaptiveColumns, spacing: 18) {
                PeerCell(id: idiom == .phone ? "iPhone" : "iPad", isThisDevice: true)
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
        .padding(idiom == .phone ? 0 : 8)
    }

    var switchLink: some View {
        SwitchToLocalLink(isForKeygen: false, selectedNetwork: $selectedNetwork)
    }
}
#endif
