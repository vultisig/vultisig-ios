//
//  KeysignDiscovery.swift
//  VoltixApp

import OSLog
import SwiftUI

struct KeysignDiscoveryView: View {
    let vault: Vault
    let keysignPayload: KeysignPayload
    @ObservedObject var sendCryptoViewModel: SendCryptoViewModel
    @Binding var keysignView: KeysignView?
    
    @StateObject var participantDiscovery = ParticipantDiscovery()
    @StateObject var viewModel = KeysignDiscoveryViewModel()
    
    @State var isLoading = false
    @State private var orientation = UIDevice.current.orientation
    
    let columns = [
        GridItem(.adaptive(minimum: 160)),
        GridItem(.adaptive(minimum: 160)),
    ]
    
    let logger = Logger(subsystem: "keysign-discovery", category: "view")
    
    var body: some View {
        ZStack {
            Background()
            view
            
            if isLoading {
                loader
            }
        }
        .detectOrientation($orientation)
        .onAppear {
            viewModel.setData(vault: vault, keysignPayload: keysignPayload, participantDiscovery: participantDiscovery)
        }
        .task {
            viewModel.startDiscovery()
        }
        .onDisappear {
            viewModel.stopDiscovery()
        }
    }
    
    var view: some View {
        VStack {
            switch viewModel.status {
            case .WaitingForDevices:
                waitingForDevices
            case .FailToStart:
                errorText
            }
        }
        .blur(radius: isLoading ? 1 : 0)
    }
    
    var loader: some View {
        Loader()
    }
    
    var errorText: some View {
        SendCryptoStartErrorView(errorText: viewModel.errorMessage)
    }
    
    var waitingForDevices: some View {
        VStack {
            content
            bottomButtons
        }
    }
    
    var content: some View {
        ZStack {
            if orientation == .landscapeLeft || orientation == .landscapeRight {
                landscapeContent
            } else {
                portraitContent
            }
        }
    }
    
    var landscapeContent: some View {
        HStack {
            paringQRCode
                .padding(60)
            list
                .padding(20)
        }
    }
    
    var portraitContent: some View {
        VStack {
            paringQRCode
            list
        }
    }
    
    var list: some View {
        ZStack {
            if participantDiscovery.peersFound.count == 0 {
                lookingForDevices
            } else {
                deviceList
            }
        }
    }
    
    var paringQRCode: some View {
        VStack {
            Text(NSLocalizedString("pairWithOtherDevices", comment: "Pair with two other devices"))
                .font(.body18MenloBold)
                .multilineTextAlignment(.center)
            
            viewModel.getQrImage(size: 100)
                .resizable()
                .scaledToFit()
                .padding()
            
            Text(NSLocalizedString("scanQrCode", comment: "Scan QR Code"))
                .font(.body13Menlo)
                .multilineTextAlignment(.center)
        }
        .foregroundColor(.neutral0)
        .cornerRadius(10)
        .shadow(radius: 5)
        .padding()
    }
    
    var lookingForDevices: some View {
        VStack {
            HStack {
                Text(NSLocalizedString("lookingForDevices", comment: "Looking for devices"))
                    .font(.body15MenloBold)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.neutral0)
                
                ProgressView()
                    .preferredColorScheme(.dark)
                    .progressViewStyle(.circular)
                    .padding(2)
            }
        }
        .cornerRadius(10)
        .shadow(radius: 5)
        .padding()
    }
    
    var deviceList: some View {
        ScrollView{
            LazyVGrid(columns: columns, spacing: 32) {
                ForEach(participantDiscovery.peersFound, id: \.self) { peer in
                    Button {
                        handleSelection(peer)
                    } label: {
                        PeerCell(id: peer, isSelected: viewModel.selections.contains(peer))
                    }
                }
            }
            .padding(20)
        }
    }
    
    var bottomButtons: some View {
        let isDisabled = viewModel.selections.count < (vault.getThreshold() + 1)
        
        return Button {
            isLoading = true
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                keysignView = viewModel.startKeysign(vault: vault, viewModel: sendCryptoViewModel)
            }
        } label: {
            FilledButton(title: "sign")
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.8 : 1)
        .grayscale(isDisabled ? 1 : 0)
        .padding(40)
    }
    
  
    func handleSelection(_ peer: String) {
        isLoading = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if viewModel.selections.contains(peer) {
                // Don't remove itself
                if peer != viewModel.localPartyID {
                    viewModel.selections.remove(peer)
                }
                isLoading = false
            } else {
                viewModel.selections.insert(peer)
                isLoading = false
            }
        }
    }
}

#Preview {
    KeysignDiscoveryView(vault: Vault.example, keysignPayload: KeysignPayload.example, sendCryptoViewModel: SendCryptoViewModel(), keysignView: .constant(nil))
}
