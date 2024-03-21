//
//  KeysignDiscovery.swift
//  VoltixApp

import OSLog
import SwiftUI

struct KeysignDiscoveryView: View {
    private let logger = Logger(subsystem: "keysign-discovery", category: "view")
    let vault: Vault
    let keysignPayload: KeysignPayload
    
    @StateObject var participantDiscovery = ParticipantDiscovery()
    @StateObject var viewModel = KeysignDiscoveryViewModel()
    
    var body: some View {
        ZStack {
            Background()
            view
        }
        .onAppear {
            self.viewModel.setData(vault: self.vault, keysignPayload: self.keysignPayload, participantDiscovery: self.participantDiscovery)
        }
        .task {
            self.viewModel.startDiscovery()
        }
        .onDisappear {
            self.viewModel.stopMediator()
        }
    }
    
    var view: some View {
        VStack {
            switch self.viewModel.status {
            case .WaitingForDevices:
                self.waitingForDevices
            case .FailToStart:
                errorText
            case .Keysign:
                keysignView
            }
        }
    }
    
    var errorText: some View {
        HStack {
            Text(NSLocalizedString("failToStart", comment: "Fail to start"))
            Text(self.viewModel.errorMessage)
        }
        .font(.body15MenloBold)
        .multilineTextAlignment(.center)
        .foregroundColor(.red)
    }
    
    var keysignView: some View {
        KeysignView(
            vault: self.vault,
            keysignCommittee: self.viewModel.selections.map { $0 },
            mediatorURL: self.viewModel.serverAddr,
            sessionID: self.viewModel.sessionID,
            keysignType: self.keysignPayload.coin.chain.signingKeyType,
            messsageToSign: self.viewModel.keysignMessages, // need to figure out all the prekeysign hashes
            keysignPayload: self.viewModel.keysignPayload
        )
    }
    
    var waitingForDevices: some View {
        VStack {
            self.paringQRCode
            if self.participantDiscovery.peersFound.count == 0 {
                self.lookingForDevices
            }
            self.deviceList
            self.bottomButtons
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
                    .progressViewStyle(.circular)
                    .padding(2)
            }
        }
        .cornerRadius(10)
        .shadow(radius: 5)
        .padding()
    }
    
    var deviceList: some View {
        List(self.participantDiscovery.peersFound, id: \.self, selection: self.$viewModel.selections) { peer in
            getPeerCell(peer)
        }
        .scrollContentBackground(.hidden)
    }
    
    var bottomButtons: some View {
        let isDisabled = viewModel.selections.count < vault.getThreshold()
        
        return Button(action: {
            self.viewModel.startKeysign()
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
            Image(systemName: self.viewModel.selections.contains(peer) ? "checkmark.circle" : "circle")
            Text(peer)
        }
        .font(.body12Menlo)
        .foregroundColor(.neutral0)
        .listRowBackground(Color.blue600)
        .onTapGesture {
            if self.viewModel.selections.contains(peer) {
                self.viewModel.selections.remove(peer)
            } else {
                self.viewModel.selections.insert(peer)
            }
        }
    }
    
    private func getQrImage(size: CGFloat) -> Image {
        let keysignMsg = KeysignMessage(sessionID: self.viewModel.sessionID, serviceName: self.viewModel.serviceName, payload: self.keysignPayload)
        
        do {
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(keysignMsg)
            
            return Utils.getQrImage(data: jsonData, size: size)
        } catch {
            self.logger.error("fail to encode keysign messages to json,error:\(error)")
        }
        
        return Image(systemName: "xmark")
    }
}
