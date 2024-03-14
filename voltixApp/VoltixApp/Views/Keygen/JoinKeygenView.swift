//
//  JoinKeygen.swift
//  VoltixApp

import CodeScanner
import Network
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "join-committee", category: "communication")

struct JoinKeygenView: View {
    let vault: Vault
    
    enum JoinKeygenStatus {
        case DiscoverSessionID
        case DiscoverService
        case JoinKeygen
        case WaitingForKeygenToStart
        case KeygenStarted
        case FailToStart
    }
    
    @State var tssType: TssType = .Keygen
    @Binding var presentationStack: [CurrentScreen]
    @State private var isShowingScanner = false
    @State private var sessionID: String? = nil
    @State private var hexChainCode: String = ""
    @ObservedObject private var serviceDelegate = ServiceDelegate()
    @State private var netService = NetService(domain: "local.", type: "_http._tcp.", name: "VoltixApp")
    @State private var currentStatus = JoinKeygenStatus.DiscoverSessionID
    @State private var keygenCommittee = [String]()
    @State var oldCommittee = [String]()
    @State var localPartyID: String = ""
    @State private var serviceName = ""
    @State var errorMessage = ""
    
    var background: some View {
        Color.backgroundBlue
            .ignoresSafeArea()
    }
    
    var body: some View {
        ZStack {
            background
            VStack {
                switch currentStatus {
                case .DiscoverSessionID:
                    discoveringSessionID
                case .DiscoverService:
                    discoveringService
                case .JoinKeygen:
                    joinKeygen
                case .WaitingForKeygenToStart:
                    waitingForKeygenStart
                case .KeygenStarted:
                    keygenStarted
                case .FailToStart:
                    failToStartKeygen
                }
            }
            .padding()
            .cornerRadius(10)
            .shadow(radius: 5)
        }
        .sheet(isPresented: $isShowingScanner, content: {
            CodeScannerView(codeTypes: [.qr], completion: self.handleScan)
        })
        .navigationTitle(NSLocalizedString("joinKeygen", comment: "Join keygen / reshare"))
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
            if !vault.localPartyID.isEmpty {
                self.localPartyID = vault.localPartyID
            } else {
                self.localPartyID = Utils.getLocalDeviceIdentity()
                vault.localPartyID = self.localPartyID
            }
        }.onDisappear {
            self.currentStatus = .FailToStart
        }
    }
    
    var scanButton: some View {
        ZStack {
            Circle()
                .foregroundColor(.blue800)
                .frame(width: 80, height: 80)
                .opacity(0.8)
            
            Circle()
                .foregroundColor(.turquoise600)
                .frame(width: 60, height: 60)
            
            Image(systemName: "camera")
                .font(.title30MenloUltraLight)
                .foregroundColor(.blue600)
        }
    }
    
    var keygenStarted: some View {
        HStack {
            if serviceDelegate.serverURL != nil && self.sessionID != nil {
                KeygenView(presentationStack: $presentationStack,
                           vault: vault,
                           tssType: tssType,
                           keygenCommittee: keygenCommittee,
                           oldParties: oldCommittee,
                           mediatorURL: serviceDelegate.serverURL!,
                           sessionID: self.sessionID!)
            } else {
                Text(NSLocalizedString("failToStartKeygen", comment: "Unable to start key generation due to missing information"))
                    .font(.body15MenloBold)
                    .foregroundColor(.neutral0)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 30)
    }
    
    var failToStartKeygen: some View {
        HStack {
            Text(errorMessage)
                .font(.body15MenloBold)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 30)
    }
    
    var discoveringSessionID: some View {
        VStack {
            Text(NSLocalizedString("scanQRCodeJoinKeygen", comment: "Scan the barcode on another VoltixApp device to start"))
                .font(.body15MenloBold)
                .foregroundColor(.neutral0)
                .multilineTextAlignment(.center)
            
            Button(action: {
                self.isShowingScanner = true
            }) {
                scanButton
            }
            
        }
    }
    
    var discoveringService: some View {
        VStack {
            HStack {
                Text("thisDevice")
                    .font(.body15MenloBold)
                    .foregroundColor(.neutral0)
                    .multilineTextAlignment(.center)
                Text(self.localPartyID)
                    .font(.body15MenloBold)
                    .foregroundColor(.neutral0)
                    .multilineTextAlignment(.center)
            }
            HStack {
                Text(NSLocalizedString("discoverinyMediator", comment: "Discovering mediator service, please wait..."))
                    .foregroundColor(.neutral0)
                    .font(.body15MenloBold)
                    .multilineTextAlignment(.center)
                
                if serviceDelegate.serverURL == nil {
                    ProgressView().progressViewStyle(.circular).padding(2)
                } else {
                    Image(systemName: "checkmark").onAppear {
                        currentStatus = .JoinKeygen
                    }
                }
            }
        }.padding(.vertical, 30)
            .onAppear {
                logger.info("Start to discover service")
                self.netService = NetService(domain: "local.", type: "_http._tcp.", name: self.serviceName)
                netService.delegate = self.serviceDelegate
                netService.resolve(withTimeout: 10)
            }
    }
    
    var joinKeygen: some View {
        VStack {
            HStack {
                Text("thisDevice")
                Text(self.localPartyID)
            }
            HStack {
                Text(NSLocalizedString("joinKeygen", comment: "Joining key generation, please wait..."))
                    .font(.body15MenloBold)
                    .multilineTextAlignment(.center)
                    .onAppear {
                        joinKeygenCommittee()
                        currentStatus = .WaitingForKeygenToStart
                    }
            }
        }.padding(.vertical, 30)
    }
    
    var waitingForKeygenStart: some View {
        VStack {
            HStack {
                Text("thisDevice")
                Text(self.localPartyID)
            }
            HStack {
                Text(NSLocalizedString("waitingForKeygenStart", comment: "Waiting for key generation to start..."))
                    .font(.body15MenloBold)
                    .multilineTextAlignment(.center)
                ProgressView().progressViewStyle(.circular).padding(2)
            }
        }
        .padding(.vertical, 30)
        .task {
            Task {
                repeat {
                    checkKeygenStarted()
                    try await Task.sleep(for: .seconds(1))
                } while self.currentStatus == .WaitingForKeygenToStart
            }
        }
    }
                     
    private func checkKeygenStarted() {
        guard let serverURL = serviceDelegate.serverURL, let sessionID = sessionID else {
            logger.error("Required information for checking key generation start is missing.")
            return
        }
                    
        let urlString = "\(serverURL)/start/\(sessionID)"
        Utils.getRequest(urlString: urlString, headers: [String: String](), completion: { result in
            switch result {
            case .success(let data):
                do {
                    let decoder = JSONDecoder()
                    let peers = try decoder.decode([String].self, from: data)
                    if peers.contains(self.localPartyID) {
                        self.keygenCommittee.append(contentsOf: peers)
                        self.currentStatus = .KeygenStarted
                    }
                } catch {
                    logger.error("Failed to decode response to JSON: \(data)")
                }
            case .failure(let error):
                logger.error("Failed to check if key generation has started, error: \(error)")
            }
        })
    }
                     
    private func joinKeygenCommittee() {
        guard let serverURL = serviceDelegate.serverURL, let sessionID = sessionID else {
            logger.error("Required information for joining key generation committee is missing.")
            return
        }
                    
        let urlString = "\(serverURL)/\(sessionID)"
        let body = [localPartyID]
        Utils.sendRequest(urlString: urlString, method: "POST", body: body) { success in
            if success {
                logger.info("Successfully joined the key generation committee.")
            }
        }
    }
                     
    private func handleScan(result: Result<ScanResult, ScanError>) {
        switch result {
        case .success(let result):
            guard let scanData = result.string.data(using: .utf8) else {
                errorMessage = "Failed to process scan data."
                currentStatus = .FailToStart
                return
            }
            do {
                let decoder = JSONDecoder()
                let result = try decoder.decode(PeerDiscoveryPayload.self, from: scanData)
                switch result {
                case .Keygen(let keysignMsg):
                    tssType = .Keygen
                    sessionID = keysignMsg.sessionID
                    hexChainCode = keysignMsg.hexChainCode
                    vault.hexChainCode = hexChainCode
                    serviceName = keysignMsg.serviceName
                case .Reshare(let reshareMsg):
                    tssType = .Reshare
                    oldCommittee = reshareMsg.oldParties
                    sessionID = reshareMsg.sessionID
                    hexChainCode = reshareMsg.hexChainCode
                    // this means the vault is new , and it join the reshare to become the new committee
                    if vault.pubKeyECDSA.isEmpty {
                        vault.hexChainCode = reshareMsg.hexChainCode
                    } else {
                        if vault.pubKeyECDSA != reshareMsg.pubKeyECDSA {
                            errorMessage = "You choose the wrong vault"
                            logger.error("The vault's public key doesn't match the reshare message's public key")
                            currentStatus = .FailToStart
                            return
                        }
                    }
                }
                            
            } catch {
                errorMessage = "Failed to decode peer discovery message: \(error.localizedDescription)"
                currentStatus = .FailToStart
                return
            }
            currentStatus = .DiscoverService
        case .failure(let error):
            errorMessage = "Failed to scan QR code: \(error.localizedDescription)"
            currentStatus = .FailToStart
            return
        }
    }
}
                     
final class ServiceDelegate: NSObject, NetServiceDelegate, ObservableObject {
    @Published var serverURL: String?
                    
    public func netServiceDidResolveAddress(_ sender: NetService) {
        logger.info("Service found: \(sender.name), \(sender.hostName ?? ""), port \(sender.port) in domain \(sender.domain)")
        serverURL = "http://\(sender.hostName ?? ""):\(sender.port)"
    }
}
                     
struct JoinKeygenView_Previews: PreviewProvider {
    static var previews: some View {
        JoinKeygenView(vault: Vault.example, presentationStack: .constant([]))
    }
}
