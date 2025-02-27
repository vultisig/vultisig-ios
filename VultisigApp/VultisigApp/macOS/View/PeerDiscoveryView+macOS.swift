//
//  PeerDiscoveryView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-18.
//

#if os(macOS)
import SwiftUI

extension PeerDiscoveryView {
    var content: some View {
        ZStack {
            GeometryReader { proxy in
                Background()
                    .clipped()
                    .onAppear {
                        setData(proxy)
                    }
                    .onChange(of: proxy.size.width) { oldValue, newValue in
                        screenWidth = proxy.size.width
                    }
                    .onChange(of: proxy.size.height) { oldValue, newValue in
                        screenHeight = proxy.size.height
                    }
            }
            
            main
        }
    }
    
    var main: some View {
        VStack {
            headerMac
            states
        }
    }
    
    var headerMac: some View {
        PeerDiscoveryHeader(
            title: "scanQR",
            vault: vault,
            selectedTab: selectedTab,
            hideBackButton: hideBackButton,
            viewModel: viewModel,
            shareSheetViewModel: shareSheetViewModel
        )
    }
    
    var landscapeContent: some View {
        HStack {
            qrCode
            
            list
                .padding(40)
        }
    }
    
    var paringBarcode: some View {
        ZStack {
            animation
            qrCodeContent
        }
        .offset(x: 24)
    }
    
    var qrCodeContent: some View {
        qrCodeImage?
            .resizable()
            .padding(32)
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: getMinSize(), maxHeight: getMinSize())
            .cornerRadius(32)
            .padding(24)
    }
    
    var animation: some View {
        animationVM.view()
    }
    
    var scrollList: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 18) {
                ThisDevicePeerCell(deviceName: "Mac")
                devices
                EmptyPeerCell(counter: participantDiscovery.peersFound.count)
            }
            .padding(.horizontal, 30)
        }
        .padding(20)
    }
    
    var gridList: some View {
        ScrollView {
            LazyVGrid(columns: adaptiveColumns, spacing: 8) {
                ThisDevicePeerCell(deviceName: "Mac")
                devices
                EmptyPeerCell(counter: participantDiscovery.peersFound.count)
            }
        }
        .scrollIndicators(.hidden)
    }
    
    var networkPrompts: some View {
        NetworkPrompts(selectedNetwork: $viewModel.selectedNetwork)
            .onChange(of: viewModel.selectedNetwork) {
                print("selected network changed: \(viewModel.selectedNetwork)")
                viewModel.restartParticipantDiscovery()
                setData()
            }
            .padding(.top, 10)
    }
    
    var devices: some View {
        ForEach(participantDiscovery.peersFound, id: \.self) { peer in
            Button {
                viewModel.handleSelection(peer)
            } label: {
                PeerCell(id: peer, isSelected: viewModel.selections.contains(peer))
            }
        }
    }
    
    var bottomButton: some View {
        let isButtonDisabled = disableContinueButton()
        
        return Button(action: {
            viewModel.startKeygen()
        }) {
            FilledButton(
                title: isButtonDisabled ? "waitingOnDevices..." : "next",
                textColor: isButtonDisabled ? .textDisabled : .blue600,
                background: isButtonDisabled ? .buttonDisabled : .turquoise600
            )
        }
        .padding(.horizontal, 40)
        .padding(.top, 20)
        .padding(.bottom, 10)
        .disabled(isButtonDisabled)
        .padding(.bottom, 30)
    }
    
    var disclaimer: some View {
        ZStack {
            if viewModel.selectedNetwork == .Local {
                LocalModeDisclaimer()
            } else if showDisclaimer {
                PeerDiscoveryScanDeviceDisclaimer(showAlert: $showDisclaimer)
            }
        }
        .padding(.leading, 24)
    }
    
    var switchLink: some View {
        SwitchToLocalLink(viewModel: viewModel)
            .padding(.bottom, 24)
    }
    
    func setData() {
        qrCodeImage = viewModel.getQrImage(size: 100)
        
        guard let qrCodeImage else {
            return
        }
        
        shareSheetViewModel.render(
            qrCodeImage: qrCodeImage,
            displayScale: displayScale,
            type: .Keygen
        )
    }
    
    func getMinSize() -> CGFloat {
        min(screenWidth/2, screenHeight/1.2)
    }
}
#endif
