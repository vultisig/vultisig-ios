//
//  PeerDiscoveryView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-18.
//

#if os(macOS)
import SwiftUI
import RiveRuntime

extension PeerDiscoveryView {
    var content: some View {
        ZStack {
            GeometryReader { proxy in
                Background()
                    .clipped()
                    .onAppear {
                        screenWidth = proxy.size.width
                        screenHeight = proxy.size.height
                        setData()
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
            title: getHeaderTitle(),
            vault: vault,
            hideBackButton: hideBackButton,
            viewModel: viewModel,
            shareSheetViewModel: shareSheetViewModel
        )
    }
    
    var portraitContent: some View {
        ScrollView {
            qrCode
            list
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
            .frame(width: getMinSize(), height: getMinSize())
    }
    
    var animation: some View {
        animationVM?.view()
    }
    
    var scrollList: some View {
        VStack {
            listTitle
            
            LazyVGrid(columns: adaptiveColumnsMac, spacing: 8) {
                ThisDevicePeerCell(deviceName: "Mac")
                devices
                EmptyPeerCell(counter: participantDiscovery.peersFound.count)
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    var networkPrompts: some View {
        NetworkPrompts(selectedNetwork: $viewModel.selectedNetwork)
            .onChange(of: viewModel.selectedNetwork) {
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
    
    @ViewBuilder
    var bottomButton: some View {
        let isButtonDisabled = disableContinueButton()
        
        PrimaryButton(title: isButtonDisabled ? "waitingOnDevices..." : "next") {
            viewModel.startKeygen()
        }
        .padding(.horizontal, 40)
        .padding(.top, 20)
        .padding(.bottom, 10)
        .disabled(isButtonDisabled)
        .padding(.bottom, 10)
    }
    
    var disclaimer: some View {
        ZStack {
            if viewModel.selectedNetwork == .Local {
                LocalModeDisclaimer()
            } else if showDisclaimer {
                if tssType != .Migrate {
                    PeerDiscoveryScanDeviceDisclaimer(showAlert: $showDisclaimer)
                } else {
                    Spacer()
                        .frame(height: 24)
                }
            }
        }
        .padding(.leading, 24)
        .padding(.horizontal, 48)
    }
    
    var switchLink: some View {
        SwitchToLocalLink(isForKeygen: true, selectedNetwork: $viewModel.selectedNetwork)
            .padding(.bottom, 24)
    }
    
    func setData() {
        qrCodeImage = viewModel.getQrImage(size: 100)
        animationVM = RiveViewModel(fileName: "QRCodeScanned", autoPlay: true)
        
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
        min(screenWidth/2.5, screenHeight/1.5)
    }
    
    private func getHeaderTitle() -> String {
        if viewModel.status == .WaitingForDevices {
            tssType == .Migrate ? "" : "scanQR"
        } else if tssType == .Migrate {
            ""
        } else {
            "creatingVault"
        }
    }
}
#endif
