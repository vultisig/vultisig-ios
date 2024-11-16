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
        .navigationTitle(getTitle())
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
    }
    
    var landscapeContent: some View {
        HStack {
            qrCode
            
            VStack {
                list
                    .padding(20)
                
                if selectedTab == .secure {
                    networkPrompts
                }
            }
        }
    }
    
    var paringBarcode: some View {
        ZStack {
            qrCodeImage?
                .resizable()
                .background(Color.blue600)
                .frame(maxWidth: 500, maxHeight: 500)
                .aspectRatio(contentMode: .fill)
                .padding(2)
                .background(Color.neutral0)
                .cornerRadius(10)
                .padding()
                .background(Color.blue600)
                .cornerRadius(15)
            
            outline
        }
        .cornerRadius(22)
        .shadow(radius: 5)
        .padding(isPhoneSE ? 8 : 20)
    }
    
    var outline: some View {
        Image("QRScannerOutline")
            .resizable()
            .frame(maxWidth: 540, maxHeight: 540)
    }
    
    var scrollList: some View {
        VStack {
            listTitle
            
            ScrollView(.horizontal) {
                HStack(spacing: 18) {
                    devices
                }
                .padding(.horizontal, 30)
            }
        }
        .padding(idiom == .phone ? 0 : 20)
    }
    
    var gridList: some View {
        ScrollView {
            listTitle
            LazyVGrid(columns: columns, spacing: 8) {
                devices
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
        Button(action: {
            viewModel.showSummary()
        }) {
            FilledButton(title: "continue")
        }
        .padding(.horizontal, 40)
        .padding(.top, 20)
        .padding(.bottom, 10)
        .disabled(disableContinueButton())
        .opacity(disableContinueButton() ? 0.8 : 1)
        .grayscale(disableContinueButton() ? 1 : 0)
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
        screenHeight = UIScreen.main.bounds.size.height
        
        if screenWidth>1100 && idiom == .pad {
            isLandscape = true
        } else {
            isLandscape = false
        }
    }
}
#endif
