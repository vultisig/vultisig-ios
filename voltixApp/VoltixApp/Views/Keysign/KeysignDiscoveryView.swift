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
    
    let logger = Logger(subsystem: "keysign-discovery", category: "view")
    
    var body: some View {
        ZStack {
            Background()
            view
        }
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
    }
    
    var errorText: some View {
        SendCryptoStartErrorView(errorText: viewModel.errorMessage)
    }
    
    var waitingForDevices: some View {
        VStack {
            paringQRCode
            if participantDiscovery.peersFound.count == 0 {
                lookingForDevices
            }
            deviceList
            bottomButtons
        }
    }
    
    var paringQRCode: some View {
        VStack {
            Text(NSLocalizedString("pairWithOtherDevices", comment: "Pair with two other devices"))
                .font(.body18MenloBold)
                .multilineTextAlignment(.center)
            
            getQrImage(size: 100)
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
        List(participantDiscovery.peersFound, id: \.self, selection: $viewModel.selections) { peer in
            getPeerCell(peer)
        }
        .scrollContentBackground(.hidden)
    }
    
    var bottomButtons: some View {
        let isDisabled = viewModel.selections.count < vault.getThreshold()
        
        return Button(action: {
            keysignView = viewModel.startKeysign(vault: vault, viewModel: sendCryptoViewModel)
        }) {
            FilledButton(title: "sign")
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.8 : 1)
        .grayscale(isDisabled ? 1 : 0)
        .padding(40)
    }
    
    private func getPeerCell(_ peer: String) -> some View {
        HStack {
            Image(systemName: viewModel.selections.contains(peer) ? "checkmark.circle" : "circle")
            Text(peer)
        }
        .font(.body12Menlo)
        .foregroundColor(.neutral0)
        .listRowBackground(Color.blue600)
        .onTapGesture {
            if viewModel.selections.contains(peer) {
                viewModel.selections.remove(peer)
            } else {
                viewModel.selections.insert(peer)
            }
        }
    }
    
    private func getQrImage(size: CGFloat) -> Image {
        let keysignMsg = KeysignMessage(sessionID: viewModel.sessionID, serviceName: viewModel.serviceName, payload: keysignPayload)
        
        do {
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(keysignMsg)
            
            return Utils.getQrImage(data: jsonData, size: size)
        } catch {
            logger.error("fail to encode keysign messages to json,error:\(error)")
        }
        
        return Image(systemName: "xmark")
    }
}
