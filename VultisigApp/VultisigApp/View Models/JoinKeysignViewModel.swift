//
//  JoinKeysignViewModel.swift
//  VultisigApp
//

import Foundation
import OSLog

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

    private let etherfaceService = EtherfaceService.shared
    private let fastVaultService = FastVaultService.shared

    @Published var isShowingScanner = false
    @Published var sessionID: String = ""
    @Published var keysignMessages = [String]()
    @Published var netService: NetService? = nil
    @Published var status = JoinKeysignStatus.DiscoverSigningMsg
    @Published var keysignCommittee = [String]()
    @Published var localPartyID: String = ""
    @Published var errorMsg: String = ""
    @Published var keysignPayload: KeysignPayload? = nil
    @Published var customMessagePayload: CustomMessagePayload? = nil
    @Published var serviceName = ""
    @Published var serverAddress: String? = nil
    @Published var useVultisigRelay = false
    @Published var isCameraPermissionGranted: Bool? = nil
    
    @Published var blowfishShow = false
    @Published var blowfishWarningsShow = false
    @Published var blowfishWarnings: [String] = []

    @Published var decodedMemo: String?

    var encryptionKeyHex: String = ""
    var payloadID: String = ""
    
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
            return logger.error("Server URL could not be found. Please ensure you're connected to the correct network.")
        }
        guard !sessionID.isEmpty else {
            return logger.error("Session ID has not been acquired. Please scan the QR code again.")
        }

        Utils.sendRequest(
            urlString: "\(serverURL)/\(sessionID)",
            method: "POST",
            headers:TssHelper.getKeysignRequestHeader(pubKey: vault.pubKeyECDSA),
            body: [localPartyID]
        ) { success in
            DispatchQueue.main.async {
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

    private func fastVaultKeysignCommittee() -> [String] {
        let fastServer = vault.signers.first(where: { $0.starts(with: "Server") })
        return [localPartyID, fastServer].compactMap { $0 }
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
                            self.keysignCommittee.removeAll()
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

    func prepareKeysignMessages(customMessagePayload: CustomMessagePayload) {
        self.keysignMessages = customMessagePayload.keysignMessages
    }

    func handleQrCodeSuccessResult(data: String?) async {
        guard let data else {
            return
        }
        
        do {
            let keysignMsg: KeysignMessage = try ProtoSerializer.deserialize(base64EncodedString: data)
            self.sessionID = keysignMsg.sessionID
            self.keysignPayload = keysignMsg.payload
            self.customMessagePayload = keysignMsg.customMessagePayload
            self.serviceName = keysignMsg.serviceName
            self.encryptionKeyHex = keysignMsg.encryptionKeyHex
            self.logger.info("QR code scanned successfully. Session ID: \(self.sessionID)")

            if let payload = keysignMsg.payload {
                self.prepareKeysignMessages(keysignPayload: payload)
            }
            if let payload = keysignMsg.customMessagePayload {
                self.prepareKeysignMessages(customMessagePayload: payload)
            }
            
            self.payloadID = keysignMsg.payloadID
            self.useVultisigRelay = keysignMsg.useVultisigRelay

            if useVultisigRelay {
                self.serverAddress = Endpoint.vultisigRelay
            }
            
            await ensureKeysignPayload()
        } catch {
            self.errorMsg = "Error decoding keysign message: \(error.localizedDescription)"
            self.status = .FailedToStart
        }
    }
    
    func manageQrCodeStates() {
        if let keysignPayload {
            if vault.pubKeyECDSA != keysignPayload.vaultPubKeyECDSA {
                self.status = .VaultMismatch
                return
            }
            
            if vault.localPartyID == keysignPayload.vaultLocalPartyID {
                self.status = .KeysignSameDeviceShare
                return
            }
        }
        if useVultisigRelay {
            self.serverAddress = Endpoint.vultisigRelay
            self.status = .JoinKeysign
        } else {
            self.status = .DiscoverService
        }
    }
    
    func ensureKeysignPayload() async  {
        if self.payloadID.isEmpty || self.keysignPayload != nil {
            return
        }
        guard let serverAddress else{
            return
        }
        
        let payloadService = PayloadService(serverURL: serverAddress)
        do{
            let payload = try await payloadService.getPayload(hash: self.payloadID)
            let kp: KeysignPayload = try ProtoSerializer.deserialize(base64EncodedString: payload)
            self.keysignPayload = kp
            self.prepareKeysignMessages(keysignPayload: kp)
        }catch{
            self.errorMsg = "Error decoding keysign message: \(error.localizedDescription)"
            self.status = .FailedToStart
        }
    }
    
    func handleDeeplinkScan(_ url: URL?) {
        guard let url else {
            return
        }
        
        guard let data = DeeplinkViewModel.getJsonData(url) else {
            return
        }
        Task{
            await handleQrCodeSuccessResult(data: data)
            DispatchQueue.main.async {
                self.manageQrCodeStates()
            }
        }
        
    }
    
    func blowfishTransactionScan() {
        blowfishShow = false
        blowfishWarningsShow = false
        blowfishWarnings = []
    }

    func loadThorchainID() async {
        do {
            _ = try await ThorchainService.shared.getTHORChainChainID()
        } catch {
            print("fail to get thorchain network id, \(error.localizedDescription)")
        }
    }

    func loadFunctionName() async {
        guard let memo = keysignPayload?.memo, keysignPayload?.coin.chainType == .EVM else {
            return
        }

        do {
            decodedMemo = try await etherfaceService.decode(memo: memo)
        } catch {
            print("Memo decoding error: \(error.localizedDescription)")
        }
    }

    func blowfishEVMTransactionScan() async throws -> BlowfishResponse {
        guard let payload = keysignPayload else {
            throw NSError(domain: "JoinKeysignViewModel", code: 2, userInfo: [NSLocalizedDescriptionKey: "Keysign payload is missing for EVM transaction scan."])
        }
        
        return try await BlowfishService.shared.blowfishEVMTransactionScan(
            fromAddress: payload.coin.address,
            toAddress: payload.toAddress,
            amountInRaw: payload.toAmount,
            memo: payload.memo,
            chain: payload.coin.chain
        )
    }
    
    func blowfishSolanaTransactionScan() async throws -> BlowfishResponse {
        guard let payload = keysignPayload else {
            throw NSError(domain: "JoinKeysignViewModel", code: 3, userInfo: [NSLocalizedDescriptionKey: "Keysign payload is missing for Solana transaction scan."])
        }
        
        let zeroSignedTransaction = try SolanaHelper.getZeroSignedTransaction(
            vaultHexPubKey: vault.pubKeyEdDSA,
            vaultHexChainCode: vault.hexChainCode,
            keysignPayload: payload
        )
        
        return try await BlowfishService.shared.blowfishSolanaTransactionScan(
            fromAddress: payload.coin.address,
            zeroSignedTransaction: zeroSignedTransaction
        )
    }
}
