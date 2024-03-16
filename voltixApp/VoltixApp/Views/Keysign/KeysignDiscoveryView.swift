//
//  KeysignDiscovery.swift
//  VoltixApp

import Dispatch
import Mediator
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "keysign-discovery", category: "view")
struct KeysignDiscoveryView: View {
    let vault: Vault
    enum KeysignDiscoveryStatus {
        case WaitingForDevices
        case FailToStart
        case Keysign
    }
    
    @State private var peersFound = [String]()
    @State private var selections = Set<String>()
    private let mediator = Mediator.shared
    private let serverAddr = "http://127.0.0.1:8080"
    @State var sessionID = ""
    @State private var currentState = KeysignDiscoveryStatus.WaitingForDevices
    @State private var localPartyID = ""
    let keysignPayload: KeysignPayload
    @State private var keysignMessages = [String]()
    @StateObject var participantDiscovery = ParticipantDiscovery()
    @State var serviceName = ""
    @State var errorMessage = ""
    
    var body: some View {
        VStack {
            switch self.currentState {
            case .WaitingForDevices:
                self.waitingForDevices
            case .FailToStart:
                HStack {
                    Text(NSLocalizedString("failToStart", comment: "Fail to start"))
                        .font(.body15MenloBold)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.red)
                    Text(self.errorMessage)
                        .font(.body15MenloBold)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.red)
                }
            case .Keysign:
                KeysignView(vault: self.vault,
                            keysignCommittee: self.selections.map { $0 },
                            mediatorURL: self.serverAddr,
                            sessionID: self.sessionID,
                            keysignType: self.keysignPayload.coin.chain.signingKeyType,
                            messsageToSign: self.keysignMessages, // need to figure out all the prekeysign hashes
                            keysignPayload: self.keysignPayload)
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
            if self.sessionID.isEmpty {
                self.sessionID = UUID().uuidString
            }
            if self.serviceName.isEmpty {
                self.serviceName = "VoltixApp-" + Int.random(in: 1 ... 1000).description
            }
            if !self.vault.localPartyID.isEmpty {
                self.localPartyID = self.vault.localPartyID
            } else {
                self.localPartyID = Utils.getLocalDeviceIdentity()
            }
            
            let keysignMessageResult = self.keysignPayload.getKeysignMessages(vault: self.vault)
            switch keysignMessageResult {
            case .success(let preSignedImageHash):
                self.keysignMessages = preSignedImageHash
                if self.keysignMessages.isEmpty {
                    logger.error("no meessage need to be signed")
                    self.currentState = .FailToStart
                }
            case .failure(let err):
                logger.error("Failed to get preSignedImageHash: \(err)")
                self.currentState = .FailToStart
            }
        }
        .task {
            // start the mediator , so other devices can discover us
            Task {
                self.mediator.start(name: self.serviceName)
                self.startKeysignSession()
            }
            self.participantDiscovery.getParticipants(serverAddr: self.serverAddr, sessionID: self.sessionID)
        }
        .onDisappear {
            logger.info("mediator server stopped")
            self.participantDiscovery.stop()
            self.mediator.stop()
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
        List(self.participantDiscovery.peersFound, id: \.self, selection: self.$selections) { peer in
            HStack {
                Image(systemName: self.selections.contains(peer) ? "checkmark.circle" : "circle")
                Text(peer)
            }
            .onTapGesture {
                if self.selections.contains(peer) {
                    self.selections.remove(peer)
                } else {
                    self.selections.insert(peer)
                }
            }
        }
        .scrollContentBackground(.hidden)
    }
    
    var bottomButtons: some View {
        Button(action: {
            self.startKeysign(allParticipants: self.selections.map { $0 })
            self.currentState = .Keysign
            self.participantDiscovery.stop()
        }) {
            FilledButton(title: "sign")
                .disabled(self.selections.count < self.vault.getThreshold())
        }
        .disabled(self.selections.count < self.vault.getThreshold())
    }
    
    private func startKeysign(allParticipants: [String]) {
        let urlString = "\(self.serverAddr)/start/\(self.sessionID)"
        Utils.sendRequest(urlString: urlString, method: "POST", body: allParticipants) { _ in
            logger.info("kicked off keysign successfully")
        }
    }
    
    private func startKeysignSession() {
        let urlString = "\(self.serverAddr)/\(self.sessionID)"
        let body = [self.localPartyID]
        Utils.sendRequest(urlString: urlString, method: "POST", body: body) { success in
            if success {
                logger.info("Started session successfully.")
            } else {
                logger.info("Failed to start session.")
            }
        }
    }
    
    func getQrImage(size: CGFloat) -> Image {
        let keysignMsg = KeysignMessage(sessionID: self.sessionID,
                                        serviceName: self.serviceName,
                                        payload: self.keysignPayload)
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
