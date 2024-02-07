//
//  JoinKeygen.swift
//  VoltixApp

#if os(iOS)
import CodeScanner
#endif
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "join-committee", category: "communication")
struct JoinKeygenView: View {
    enum JoinKeygenStatus {
        case DiscoverSessionID
        case DiscoverService
        case JoinKeygen
        case WaitingForKeygenToStart
        case KeygenStarted
        case FailToStart
    }

    @EnvironmentObject var appState: ApplicationState
    @Binding var presentationStack: [CurrentScreen]
    @State private var isShowingScanner = false
    @State private var qrCodeResult: String? = nil
    @ObservedObject private var serviceDelegate = ServiceDelegate()
    private let netService = NetService(domain: "local.", type: "_http._tcp.", name: "VoltixApp")
    @State private var currentStatus = JoinKeygenStatus.DiscoverService
    @State private var keygenCommittee = [String]()
    @State var localPartyID: String = ""
    
    var body: some View {
        VStack {
            switch currentStatus {
            case .DiscoverSessionID:
                Text("Scan the barcode on another VoltixApp")
                Button("Scan", systemImage: "qrcode.viewfinder") {
                    isShowingScanner = true
                }
                .sheet(isPresented: $isShowingScanner, content: {
                    #if os(iOS)
                    CodeScannerView(codeTypes: [.qr], completion: self.handleScan)
                    #endif
                })
            case .DiscoverService:
                HStack {
                    Text("discovering mediator service")
                    if serviceDelegate.serverUrl == nil {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.blue)
                            .padding(2)
                    } else {
                        Image(systemName: "checkmark").foregroundColor(/*@START_MENU_TOKEN@*/ .blue/*@END_MENU_TOKEN@*/).onAppear {
                            currentStatus = .DiscoverSessionID
                        }
                    }
                }
            case .JoinKeygen:
                Text("Join Keygen to create a new wallet").onAppear {
                    joinKeygenCommittee()
                    currentStatus = .WaitingForKeygenToStart
                }
            case .WaitingForKeygenToStart:
                HStack {
                    Text("Waiting for keygen to start")
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.blue)
                        .padding(2)
                }.task {
                    Task {
                        repeat {
                            checkKeygenStarted()
                            try await Task.sleep(nanoseconds: 1_000_000_000)
                        } while self.currentStatus == .WaitingForKeygenToStart
                    }
                }
            case .KeygenStarted:
                HStack {
                    if serviceDelegate.serverUrl != nil && self.qrCodeResult != nil {
                        // at here we already know these two optional has values
                        KeygenView(presentationStack: $presentationStack,
                                   keygenCommittee: keygenCommittee,
                                   mediatorURL: serviceDelegate.serverUrl ?? "",
                                   sessionID: self.qrCodeResult ?? "",
                                   localPartyKey: self.localPartyID,
                                   vaultName: appState.creatingVault?.name ?? "New Vault")
                    } else {
                        Text("Mediator server url is empty or session id is empty")
                    }
                }.navigationBarBackButtonHidden(true)
            case .FailToStart:
                // TODO: update this message to be more friendly, it shouldn't happen
                Text("fail to start")
            }
            
        }.onAppear {
            logger.info("start to discover service")
            netService.delegate = self.serviceDelegate
            netService.resolve(withTimeout: TimeInterval(10))
            // by this step , creatingVault should be available already
            if appState.creatingVault == nil {
                self.currentStatus = .FailToStart
            }
            
            if let localPartyID = appState.creatingVault?.localPartyID, !localPartyID.isEmpty {
                self.localPartyID = localPartyID
            } else {
                self.localPartyID = Utils.getLocalDeviceIdentity()
                appState.creatingVault?.localPartyID = self.localPartyID
            }
        }
    }
    
    private func checkKeygenStarted() {
        guard let serverUrl = serviceDelegate.serverUrl else {
            logger.error("didn't discover server url")
            return
        }
        guard let sessionID = qrCodeResult else {
            logger.error("session id has not acquired")
            return
        }
        
        let urlString = "\(serverUrl)/start/\(sessionID)"
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
                    logger.error("Failed to decode response to JSON, \(data)")
                }
            case .failure(let error):
                let err = error as NSError
                if err.code == 404 {
                    return
                }
                logger.error("Failed to check keygen started, error: \(error)")
            }
            
        })
    }
    
    private func joinKeygenCommittee() {
        guard let serverUrl = serviceDelegate.serverUrl else {
            logger.error("didn't discover server url")
            return
        }
        guard let sessionID = qrCodeResult else {
            logger.error("session id has not acquired")
            return
        }
        
        let urlString = "\(serverUrl)/\(sessionID)"
        let body = [localPartyID]
        Utils.sendRequest(urlString: urlString, method: "POST", body: body) { success in
            if success {
                logger.info("Joined keygen committee successfully.")
            }
        }
    }

    #if os(iOS)
    private func handleScan(result: Result<ScanResult, ScanError>) {
        switch result {
        case .success(let result):
            qrCodeResult = result.string
            logger.debug("session id: \(result.string)")
        case .failure(let err):
            logger.error("fail to scan QR code,error:\(err.localizedDescription)")
        }
        currentStatus = .JoinKeygen
    }
    #endif
}

final class ServiceDelegate: NSObject, NetServiceDelegate, ObservableObject {
    @Published var serverUrl: String?
    public func netServiceDidResolveAddress(_ sender: NetService) {
        logger.info("find service:\(sender.name) , \(sender.hostName ?? "") , \(sender.port) \(sender.domain) \(sender)")
        serverUrl = "http://\(sender.hostName ?? ""):\(sender.port)"
    }
}

#Preview {
    JoinKeygenView(presentationStack: .constant([]))
}
