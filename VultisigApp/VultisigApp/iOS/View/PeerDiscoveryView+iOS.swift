//
//  PeerDiscoveryView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-18.
//

#if os(iOS)
import SwiftUI

extension PeerDiscoveryView {
    private var idiom : UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
    
    var content: some View {
        ZStack {
            GeometryReader { proxy in
                Background()
                    .onAppear {
                        setData(proxy)
                    }
            }
            
            main
        }
        .navigationTitle("scanQR")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(hideBackButton)
        .detectOrientation($orientation)
        .onChange(of: orientation) { oldValue, newValue in
            setData()
        }
        .toolbar {
            // only show the QR share button when it is in peer discovery
            if isShareButtonVisible {
                ToolbarItem(placement: Placement.topBarTrailing.getPlacement()) {
                    NavigationQRShareButton(
                        vault: vault,
                        type: .Keygen,
                        renderedImage: shareSheetViewModel.renderedImage
                    )
                }
            }
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
            .sheet(isPresented: $showInfoSheet) {
                PeerDiscoveryInfoBanner(isPresented: $showInfoSheet)
                    .presentationDetents([.height(450)])
            }
    }
    
    var landscapeContent: some View {
        HStack {
            qrCode
            
            VStack {
                list
                    .padding(20)
            }
        }
    }
    
    var paringBarcode: some View {
        ZStack {
            animation
            qrCodeContent
        }
        .padding(isPhoneSE ? 8 : 20)
    }
    
    var qrCodeContent: some View {
        qrCodeImage?
            .resizable()
            .frame(maxWidth: 500, maxHeight: 500)
            .aspectRatio(contentMode: .fill)
            .padding(16)
            .background(Color.blue600)
            .cornerRadius(38)
            .padding(2)
    }
    
    var animation: some View {
        animationVM.view()
    }
    
    var scrollList: some View {
        VStack {
            listTitle
            
            ScrollView {
                LazyVGrid(columns: phoneColumns, spacing: 18) {
                    devices
                    EmptyPeerCell(counter: participantDiscovery.peersFound.count)
                }
                .padding(.horizontal, 18)
            }
        }
    }
    
    var gridList: some View {
        ScrollView {
            listTitle
            LazyVGrid(columns: isLandscape ? phoneColumns : columns, spacing: 8) {
                devices
                EmptyPeerCell(counter: participantDiscovery.peersFound.count)
            }
            .padding(idiom == .phone ? 0 : 20)
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
    
    var bottomButton: some View {
        let isButtonDisabled = disableContinueButton()
        
        return Button(action: {
            viewModel.showSummary()
        }) {
            FilledButton(
                title: isButtonDisabled ? "waitingOnDevices..." : "next",
                textColor: isButtonDisabled ? .textDisabled : .blue600,
                background: isButtonDisabled ? .buttonDisabled : .turquoise600
            )
        }
        .padding(.horizontal, 40)
        .padding(.top, 20)
        .padding(.bottom, idiom == .phone ? 10 : 30)
        .disabled(isButtonDisabled)
    }

    var isShareButtonVisible: Bool {
        return viewModel.status == .WaitingForDevices && selectedTab.hasOtherDevices
    }

    func setData() {
        updateScreenSize()
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
    
    private func updateScreenSize() {
        screenWidth = UIScreen.main.bounds.size.width
        
        if screenWidth>1050 && idiom == .pad {
            isLandscape = true
        } else {
            isLandscape = false
        }
    }
}
#endif
