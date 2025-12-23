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
        .showIf(viewModel.status != .Keygen)
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
            qrCodeImage?
                .resizable()
                .frame(width: getMinSize(), height: getMinSize())
                .padding(24)
        }
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
                EmptyPeerCell()
            }
            .animation(.easeInOut(duration: 0.2), value: viewModel.selections)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }
    
    var networkPrompts: some View {
        NetworkPrompts(selectedNetwork: $viewModel.selectedNetwork)
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
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 10)
        .disabled(isButtonDisabled)
        .padding(.bottom, 10)
        .animation(.easeInOut(duration: 0.2), value: isButtonDisabled)
    }
    
    var switchLink: some View {
        SwitchToLocalLink(isForKeygen: true, selectedNetwork: $viewModel.selectedNetwork)
            .padding(.bottom, 24)
    }
    
    func setData() {
        guard let (qrCodeString, qrCodeImage) = viewModel.getQRCodeData(size: 500, displayScale: displayScale) else {
            return
        }
        self.qrCodeImage = qrCodeImage
        animationVM = RiveViewModel(fileName: "QRCodeScanned", autoPlay: true)
        shareSheetViewModel.render(
            qrCodeImage: qrCodeImage,
            qrCodeData: qrCodeString,
            displayScale: displayScale,
            type: .Keygen
        )
    }
    
    func getMinSize() -> CGFloat {
        min(screenWidth/2.5, screenHeight/2.5)
    }
    
    
}
#endif
