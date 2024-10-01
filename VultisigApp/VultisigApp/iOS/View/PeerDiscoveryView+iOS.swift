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
        .detectOrientation($orientation)
        .onChange(of: viewModel.selections) {
            setNumberOfPairedDevices()
        }
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
                vaultDetail
            }
        }
    }
    
    var paringBarcode: some View {
        ZStack {
            qrCodeImage?
                .resizable()
                .background(Color.blue600)
                .frame(maxWidth: isPhoneSE ? 250 : nil)
                .frame(maxHeight: isPhoneSE ? 250 : nil)
                .aspectRatio(
                    contentMode:
                        participantDiscovery.peersFound.count == 0 && idiom == .phone ?
                        .fill :
                            .fit
                )
                .padding(2)
                .frame(maxHeight: .infinity)
                .background(Color.neutral0)
                .cornerRadius(10)
                .padding()
                .background(Color.blue600)
                .cornerRadius(15)
                .overlay (
                    RoundedRectangle(cornerRadius: 15)
                        .strokeBorder(Color.turquoise600, style: StrokeStyle(lineWidth: 2, dash: [58]))
                )
                .padding(1)
        }
        .cornerRadius(10)
        .shadow(radius: 5)
        .padding(isPhoneSE ? 8 : 20)
    }
    
    var scrollList: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 18) {
                devices
            }
            .padding(.horizontal, 30)
        }
        .padding(idiom == .phone ? 0 : 20)
    }
    
    var gridList: some View {
        ScrollView {
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
            title: "joinKeygen",
            qrCodeImage: qrCodeImage,
            displayScale: displayScale
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
