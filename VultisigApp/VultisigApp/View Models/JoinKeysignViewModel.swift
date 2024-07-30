//
//  JoinKeysignViewModel.swift
//  VultisigApp
//

import Foundation
import OSLog

#if os(iOS)
import CodeScanner
#endif

enum JoinKeysignStatus {
    case DiscoverSigningMsg
    case DiscoverService
    case JoinKeysign
    case WaitingForKeysignToStart
    case KeysignStarted
    case FailedToStart
    case VaultMismatch
    case KeysignSameDeviceShare
    case KeysignNoCameraAccess
}
@MainActor
class JoinKeysignViewModel: ObservableObject {
    private let logger = Logger(subsystem: "join-keysign", category: "viewmodel")
    var vault: Vault
    var serviceDelegate: ServiceDelegate?
    
    @Published var isShowingScanner = false
    @Published var sessionID: String = ""
    @Published var keysignMessages = [String]()
    @Published var netService: NetService? = nil
    @Published var status = JoinKeysignStatus.DiscoverSigningMsg
    @Published var keysignCommittee = [String]()
    @Published var localPartyID: String = ""
    @Published var errorMsg: String = ""
    @Published var keysignPayload: KeysignPayload? = nil
    @Published var serviceName = ""
    @Published var serverAddress: String? = nil
    @Published var useVultisigRelay = false
    @Published var isCameraPermissionGranted: Bool? = nil
    
    var encryptionKeyHex: String = ""
    
    init() {
        self.vault = Vault(name: "Main Vault")
        self.isShowingScanner = false
    }
    
    func setData(vault: Vault, serviceDelegate: ServiceDelegate, isCameraPermissionGranted: Bool) {
        self.vault = vault
        self.serviceDelegate = serviceDelegate
        self.isCameraPermissionGranted = isCameraPermissionGranted
        
        if !self.vault.localPartyID.isEmpty {
            self.localPartyID = self.vault.localPartyID
        } else {
            self.localPartyID = Utils.getLocalDeviceIdentity()
        }
        
        if let isAllowed = self.isCameraPermissionGranted, !isAllowed {
            status = .KeysignNoCameraAccess
        }
    }
    
    func startScan() {
        self.isShowingScanner = true
    }
    
    func joinKeysignCommittee() {
        guard let serverURL = serverAddress else {
            self.logger.error("Server URL could not be found. Please ensure you're connected to the correct network.")
            return
        }
        guard !self.sessionID.isEmpty else {
            self.logger.error("Session ID has not been acquired. Please scan the QR code again.")
            return
        }
        
        let urlString = "\(serverURL)/\(sessionID)"
        let body = [self.localPartyID]
        
        Utils.sendRequest(urlString: urlString,
                          method: "POST",
                          headers:TssHelper.getKeysignRequestHeader(pubKey: vault.pubKeyECDSA),
                          body: body) { success in
            DispatchQueue.main.async{
                if success {
                    self.logger.info("Successfully joined the keysign committee.")
                    self.status = .WaitingForKeysignToStart
                } else {
                    self.errorMsg = "Failed to join the keysign committee. Please check your connection and try again."
                    self.status = .FailedToStart
                }
            }
        }
    }
    
    func setStatus(status: JoinKeysignStatus) {
        self.status = status
    }
    
    func discoverService() {
        self.netService = NetService(domain: "local.", type: "_http._tcp.", name: self.serviceName)
        self.netService?.delegate = self.serviceDelegate
        self.netService?.resolve(withTimeout: 10)
    }
    func stopJoiningKeysign(){
        self.status = .DiscoverSigningMsg
    }
    func waitForKeysignStart() async {
        do {
            let t = Task {
                repeat {
                    self.checkKeysignStarted()
                    try await Task.sleep(for: .seconds(1))
                } while self.status == .WaitingForKeysignToStart
            }
            try await t.value
        } catch {
            self.logger.error("Failed to wait for keysign to start.")
        }
    }
    
    private func checkKeysignStarted() {
        guard let serverURL = serverAddress else {
            self.logger.error("Server URL could not be found. Please ensure you're connected to the correct network.")
            return
        }
        guard !self.sessionID.isEmpty else {
            self.logger.error("Session ID has not been acquired. Please scan the QR code again.")
            return
        }
        
        let urlString = "\(serverURL)/start/\(sessionID)"
        Utils.getRequest(urlString: urlString,
                         headers: TssHelper.getKeysignRequestHeader(pubKey: vault.pubKeyECDSA),
                         completion: { result in
            switch result {
            case .success(let data):
                DispatchQueue.main.async {
                    do {
                        let decoder = JSONDecoder()
                        let peers = try decoder.decode([String].self, from: data)
                        if peers.contains(self.localPartyID) {
                            self.keysignCommittee.append(contentsOf: peers)
                            self.status = .KeysignStarted
                            self.logger.info("Keysign process has started successfully.")
                        }
                    } catch {
                        self.errorMsg = "There was an issue processing the keysign start response. Please try again."
                        self.status = .FailedToStart
                    }
                }
            case .failure(let error):
                let err = error as NSError
                if err.code == 404 {
                    self.logger.info("Waiting for keysign to start. Please stand by.")
                } else {
                    self.errorMsg = "Failed to verify keysign start. Error: \(error.localizedDescription)"
                    self.status = .FailedToStart
                }
            }
        })
    }
    
#if os(iOS)
    // Scan the QR code and strip the data
    func handleScan(result: Result<ScanResult, ScanError>) {
        defer {
            self.isShowingScanner = false
        }
        
        guard let isCameraPermissionGranted, isCameraPermissionGranted else {
            status = .KeysignNoCameraAccess
            return
        }
        
        switch result {
        case .success(let result):
            guard let data = DeeplinkViewModel.getJsonData(URL(string: result.string)) else {
                return
            }
            handleQrCodeSuccessResult(data: data)
        case .failure(let err):
            self.errorMsg = "QR code scanning failed: \(err.localizedDescription)"
            self.status = .FailedToStart
        }
        
        manageQrCodeStates()
    }
#endif
    
    func prepareKeysignMessages(keysignPayload: KeysignPayload) {
        do {
            let keysignFactory = KeysignMessageFactory(payload: keysignPayload)
            let preSignedImageHash = try keysignFactory.getKeysignMessages(vault: vault)
            self.logger.info("Successfully prepared messages for keysigning.")
            self.keysignMessages = preSignedImageHash.sorted()
            if self.keysignMessages.isEmpty {
                self.errorMsg = "There is no messages to be signed"
                self.status = .FailedToStart
            }
        } catch {
            self.errorMsg = "Failed to prepare messages for keysigning. Error: \(error.localizedDescription)"
            self.status = .FailedToStart
        }
    }
    
    func handleQrCodeSuccessResult(data: String?) {
        guard let data else {
            return
        }
        
        do {
            let keysignMsg: KeysignMessage = try ProtoSerializer.deserialize(base64EncodedString: data)
            self.sessionID = keysignMsg.sessionID
            self.keysignPayload = keysignMsg.payload
            self.serviceName = keysignMsg.serviceName
            self.encryptionKeyHex = keysignMsg.encryptionKeyHex
            self.logger.info("QR code scanned successfully. Session ID: \(self.sessionID)")
            self.prepareKeysignMessages(keysignPayload: keysignMsg.payload)
            useVultisigRelay = keysignMsg.useVultisigRelay
        } catch {
            self.errorMsg = "Error decoding keysign message: \(error.localizedDescription)"
            self.status = .FailedToStart
        }
    }
    
    func manageQrCodeStates() {
        if vault.pubKeyECDSA != keysignPayload?.vaultPubKeyECDSA {
            self.status = .VaultMismatch
            return
        }
        
        if vault.localPartyID == keysignPayload?.vaultLocalPartyID {
            self.status = .KeysignSameDeviceShare
            return
        }
        
        if useVultisigRelay {
            self.serverAddress = Endpoint.vultisigRelay
            self.status = .JoinKeysign
        } else {
            self.status = .DiscoverService
        }
    }
    
    func handleDeeplinkScan(_ url: URL?) {
        guard let url else {
            return
        }
        
        guard let data = DeeplinkViewModel.getJsonData(url) else {
            return
        }
        handleQrCodeSuccessResult(data: data)
        manageQrCodeStates()
    }
    
    func blowfishEVMTransactionScan() async throws -> BlowfishEvmResponse? {
        
        guard let payload = keysignPayload else {
            return nil
        }
        
        return try await BlowfishService.shared.blowfishEVMTransactionScan(
            fromAddress: payload.coin.address,
            toAddress: payload.toAddress,
            amountInRaw: payload.toAmount,
            memo: payload.memo,
            chain: payload.coin.chain
        )
    }
    
    func blowfishSolanaTransactionScan() async throws -> BlowfishEvmResponse? {
        
        guard let payload = keysignPayload else {
            return nil
        }
        
//        let unsignedTx = try SolanaHelper.getUnsignedTransaction(keysignPayload: payload);
//        
//        print(unsignedTx)
//        
//        return try await BlowfishService.shared.blowfishSolanaTransactionScan(fromAddress: payload.coin.address, unsignedTransaction: unsignedTx);
        
        return nil
    }
}
