//
//  PeerDiscoveryView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-18.
//

#if os(iOS)
import SwiftUI
import RiveRuntime

extension PeerDiscoveryView {
    private var idiom : UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
    
    var content: some View {
        ZStack {
            Background()
            main
        }
        .crossPlatformToolbar("scanQR".localized) {
            
            CustomToolbarItem(placement: .trailing) {
                if isShareButtonVisible {
                    NavigationQRShareButton(
                        vault: vault,
                        type: .Keygen,
                        viewModel: shareSheetViewModel
                    )
                }
            }
        }
        .navigationBarBackButtonHidden(hideBackButton)
        .detectOrientation($orientation)
        .onChange(of: orientation) { oldValue, newValue in
            setData()
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
    
    var main: some View {
        states
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
        .padding(8)
    }
    
    var qrCodeContent: some View {
        qrCodeImage?
            .resizable()
            .frame(maxWidth: 500, maxHeight: 500)
            .aspectRatio(contentMode: .fill)
            .padding(16)
            .background(Color.clear)
            .cornerRadius(38)
            .padding(2)
    }
    
    var animation: some View {
        animationVM?.view()
    }
    
    var scrollList: some View {
        VStack {
            listTitle
            
            LazyVGrid(columns: adaptiveColumns, spacing: 18) {
                ThisDevicePeerCell(deviceName: idiom == .phone ? "iPhone" : "iPad")
                devices
                EmptyPeerCell(counter: participantDiscovery.peersFound.count)
            }
            .padding(.horizontal, 12)
            .animation(.easeInOut(duration: 0.2), value: viewModel.selections)
        }
        .frame(maxWidth: .infinity)
    }
    
    var networkPrompts: some View {
        NetworkPrompts(selectedNetwork: $viewModel.selectedNetwork)
            .padding(.top, idiom == .pad ? 10 : 2)
    }
    
    var devices: some View {
        ForEach(participantDiscovery.peersFound, id: \.self) { peer in
            Button {
                viewModel.handleSelection(peer)
            } label: {
                PeerCell(id: peer, isSelected: viewModel.selections.contains(peer))
            }
        }
        .padding(idiom == .phone ? 0 : 8)
    }
    
    @ViewBuilder
    var bottomButton: some View {
        let isButtonDisabled = disableContinueButton()
        
        PrimaryButton(title: isButtonDisabled ? "waitingOnDevices..." : "next") {
            viewModel.startKeygen()
        }
        .padding(.horizontal, 40)
        .padding(.top, 20)
        .padding(.bottom, idiom == .phone ? 10 : 30)
        .disabled(isButtonDisabled)
        .animation(.easeInOut(duration: 0.2), value: isButtonDisabled)
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
        .padding(.horizontal, idiom == .pad ? 24 : 12)
    }
    
    var switchLink: some View {
        SwitchToLocalLink(isForKeygen: true, selectedNetwork: $viewModel.selectedNetwork)
            .disabled(viewModel.isLoading)
    }
    
    var isShareButtonVisible: Bool {
        return viewModel.status == .WaitingForDevices && selectedTab.hasOtherDevices
    }
    
    func setData() {
        guard let (qrCodeString, qrCodeImage) = viewModel.getQRCodeData(size: 100) else {
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
}
#endif
