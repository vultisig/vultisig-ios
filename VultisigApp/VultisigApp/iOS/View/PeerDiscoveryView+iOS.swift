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
    private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }

    var qrCodeSize: CGFloat {
        screenHeight / 3.5
    }

    var content: some View {
        GeometryReader { proxy in
            ZStack {
                Background()
                main
            }
            .onAppear {
                screenHeight = proxy.size.height
                setData()
            }
            .crossPlatformToolbar(NSLocalizedString(getHeaderTitle(), comment: "")) {
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
        }
        .navigationBarBackButtonHidden(hideBackButton)
        .detectOrientation($orientation)
        .onChange(of: orientation) { _, _ in
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
            VStack(spacing: 16) {
                qrCode
                list
            }
        }
    }

    var paringBarcode: some View {
        ZStack {
            animation
            qrCodeImage?
                .resizable()
                .frame(maxWidth: qrCodeSize, maxHeight: qrCodeSize)
                .padding(20)
        }
    }

    var animation: some View {
        animationVM?.view()
    }

    var scrollList: some View {
        VStack(alignment: .leading, spacing: 24) {
            listTitle
            LazyVGrid(columns: adaptiveColumns, spacing: 12) {
                ThisDevicePeerCell(deviceName: idiom == .phone ? "iPhone" : "iPad")
                devices
                EmptyPeerCell()
            }
            .animation(.easeInOut(duration: 0.2), value: viewModel.selections)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, idiom == .pad ? 24 : 16)
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

    var switchLink: some View {
        SwitchToLocalLink(isForKeygen: true, selectedNetwork: $viewModel.selectedNetwork)
            .disabled(viewModel.isLoading)
    }

    var isShareButtonVisible: Bool {
        return viewModel.status == .WaitingForDevices && selectedTab.hasOtherDevices
    }

    func setData() {
        guard self.qrCodeImage == nil, qrCodeSize > 0 else { return }
        guard let (qrCodeString, qrCodeImage) = viewModel.getQRCodeData(size: qrCodeSize, displayScale: displayScale) else {
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
