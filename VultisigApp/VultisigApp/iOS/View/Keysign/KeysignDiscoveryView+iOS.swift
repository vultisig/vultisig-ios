//
//  KeysignDiscoveryView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-19.
//

#if os(iOS)
import SwiftUI

extension KeysignDiscoveryView {
    private var idiom : UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
    
    var container: some View {
        content
            .detectOrientation($orientation)
            .onAppear {
                setSize()
            }
            .onChange(of: screenWidth) { oldValue, newValue in
                setSize()
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
    }
    
    var orientedContent: some View {
        ZStack {
            if orientation == .landscapeLeft || orientation == .landscapeRight || isiOSAppOnMac {
                landscapeContent
            } else {
                portraitContent
            }
        }
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
            .padding(16)
            .background(Color.clear)
            .cornerRadius(38)
            .padding(2)
    }
    
    var signButton: some View {
        let isDisabled = viewModel.selections.count < (vault.getThreshold() + 1)
        
        return Button(action: {
            isLoading = true
            startKeysign()
        }) {
            FilledButton(
                title: isDisabled ? "waitingOnDevices..." : "sign",
                textColor: isDisabled ? .textDisabled : .blue600,
                background: isDisabled ? .buttonDisabled : .turquoise600
            )
        }
        .disabled(isDisabled)
        .padding(.horizontal, 32)
        .edgesIgnoringSafeArea(.bottom)
        .padding(2)
    }
    
    var deviceList: some View {
        VStack {
            listTitle
            
            LazyVGrid(columns: columns, spacing: 18) {
                ThisDevicePeerCell(deviceName: idiom == .phone ? "iPhone" : "iPad")
                devices
                EmptyPeerCell(counter: participantDiscovery.peersFound.count)
            }
            .padding(.horizontal, 18)
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
        SwitchToLocalLink(selectedNetwork: $selectedNetwork)
    }
    
    private func setSize() {
        getQRSize()
        getQROutline()
        maxSize()
    }
    
    private func maxSize() {
        minWidth = min(screenHeight*0.8, screenWidth/2.5)
    }
    
    private func getQRSize() {
        guard !isiOSAppOnMac else {
            let width = screenWidth/2 - 100
            qrSize = min(width, screenHeight/2)
            return
        }
        
        guard !isPhoneSE else {
            qrSize = 250
            return
        }
        
        guard idiom == .phone else {
            qrSize = screenWidth-335
            return
        }
        
        qrSize = screenWidth-80
    }
    
    private func getQROutline() {
        guard !isiOSAppOnMac else {
            let width = screenWidth/2 + 10
            qrOutlineSize = min(width, screenHeight/2 + 110)
            return
        }
        
        guard !isPhoneSE else {
            qrOutlineSize = 280
            return
        }
        
        guard idiom == .phone else {
            qrOutlineSize = screenWidth-300
            return
        }
        
        qrOutlineSize = screenWidth-45
    }
}
#endif
