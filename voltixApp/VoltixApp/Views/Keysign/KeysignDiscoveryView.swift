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
        VStack {
            switch self.viewModel.status {
            case .WaitingForDevices:
                self.waitingForDevices
            case .FailToStart:
                HStack {
                    Text(NSLocalizedString("failToStart", comment: "Fail to start"))
                        .font(.body15MenloBold)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.red)
                    Text(self.viewModel.errorMessage)
                        .font(.body15MenloBold)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.red)
                }
            case .Keysign:
                KeysignView(vault: self.vault,
                            keysignCommittee: self.viewModel.selections.map { $0 },
                            mediatorURL: self.viewModel.serverAddr,
                            sessionID: self.viewModel.sessionID,
                            keysignType: self.keysignPayload.coin.chain.signingKeyType,
                            messsageToSign: self.viewModel.keysignMessages, // need to figure out all the prekeysign hashes
                            keysignPayload: self.viewModel.keysignPayload)
            }
        }
        .navigationTitle(NSLocalizedString("mainDevice", comment: "Main Device"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationBackButton()
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationHelpButton()
            }
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
    
    var background: some View {
        Color.backgroundBlue
            .ignoresSafeArea()
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
            
            self.getQrImage(size: 100)
                .resizable()
                .scaledToFit()
                .padding()
            
            Text(NSLocalizedString("scanQrCode", comment: "Scan QR Code"))
                .font(.body13Menlo)
                .multilineTextAlignment(.center)
        }
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
            HStack {
                Image(systemName: self.viewModel.selections.contains(peer) ? "checkmark.circle" : "circle")
                Text(peer)
            }
            .onTapGesture {
                if self.viewModel.selections.contains(peer) {
                    self.viewModel.selections.remove(peer)
                } else {
                    self.viewModel.selections.insert(peer)
                }
            }
        }
        .scrollContentBackground(.hidden)
    }
    
    var bottomButtons: some View {
        Button(action: {
            self.viewModel.startKeysign()
        }) {
            FilledButton(title: "sign")
                .disabled(self.viewModel.selections.count < self.vault.getThreshold())
        }
        .disabled(self.viewModel.selections.count < self.vault.getThreshold())
    }
    
    func getQrImage(size: CGFloat) -> Image {
        let keysignMsg = KeysignMessage(sessionID: self.viewModel.sessionID,
                                        serviceName: self.viewModel.serviceName,
                                        payload: self.keysignPayload)
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
