//
//  JoinKeysignViewModel.swift
//  VultisigApp
//

import Foundation
import OSLog
import BigInt
import SwiftData
import SwiftUI

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
    case VaultTypeDoesntMatch
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
    @Published var customMessagePayload: CustomMessagePayload? = nil
    @Published var serviceName = ""
    @Published var serverAddress: String? = nil
    @Published var useVultisigRelay = false
    @Published var isCameraPermissionGranted: Bool? = nil
    
    @Published var decodedMemo: String?
    
    var encryptionKeyHex: String = ""
    var payloadID: String = ""
    
    init() {
        self.vault = Vault(name: "Main Vault")
        self.isShowingScanner = false
    }

    func getSpender() -> String {
        return keysignPayload?.approvePayload?.spender ?? .empty
    }

    func getAmount() -> String {
        guard let fromCoin = keysignPayload?.coin, let amount = keysignPayload?.approvePayload?.amount else {
            return .empty
        }

        return "\(fromCoin.decimal(for: amount).formatDecimalToLocale()) \(fromCoin.ticker)"
    }
    
    private func fetchVaults() -> [Vault] {
        let fetchVaultDescriptor = FetchDescriptor<Vault>()
        do {
            return try Storage.shared.modelContext.fetch(fetchVaultDescriptor)
        } catch {
            logger.error("Failed to fetch vaults: \(error.localizedDescription)")
            return []
        }
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
            
            // Decode custom message if present
            if let customMessage = keysignMsg.customMessagePayload {
                if let decodedMessage = await customMessage.message.decodedExtensionMemoAsync() {
                    self.customMessagePayload?.decodedMessage = decodedMessage
                }
            }
            
            // Auto-select correct vault BEFORE preparing messages
            if let keysignPayload = keysignMsg.payload {
                if vault.pubKeyECDSA != keysignPayload.vaultPubKeyECDSA {
                    if let correctVault = fetchVaults().first(where: { $0.pubKeyECDSA == keysignPayload.vaultPubKeyECDSA }) {
                        self.vault = correctVault
                        self.localPartyID = correctVault.localPartyID.isEmpty ? Utils.getLocalDeviceIdentity() : correctVault.localPartyID
                        logger.info("Auto-selected correct vault: \(correctVault.name) with pubKey: \(correctVault.pubKeyECDSA)")
                    }
                }
            }
            
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
            // only compare libType when it is not empty
            if !keysignPayload.libType.isEmpty {
                let libType = vault.libType ?? .GG20
                if libType != keysignPayload.libType.toLibType() {
                    self.status = .VaultTypeDoesntMatch
                    return
                }
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
    
    func loadThorchainID() async {
        do {
            _ = try await ThorchainService.shared.getTHORChainChainID()
        } catch {
            print("fail to get thorchain network id, \(error.localizedDescription)")
        }
    }
    
    func loadFunctionName() async {
        guard let memo = keysignPayload?.memo, !memo.isEmpty else {
            return
        }
        
        // Use async decoding for proper function selector resolution
        if let extensionDecoded = await memo.decodedExtensionMemoAsync() {
            decodedMemo = extensionDecoded
            return
        }
        
        // Fall back to EVM-specific decoding for EVM chains
        guard keysignPayload?.coin.chainType == .EVM else {
            return
        }
        
        do {
            let evmDecoded = try await MemoDecodingService.shared.decode(memo: memo)
            decodedMemo = evmDecoded
        } catch {
            print("EVM memo decoding error: \(error.localizedDescription)")
        }
    }
    
    func getCalculatedNetworkFee() -> String {
        guard let payload = keysignPayload else {
            return .zero
        }

        guard let nativeToken = TokensStore.TokenSelectionAssets.first(where: {
            $0.isNativeToken && $0.chain == payload.coin.chain
        }) else {
            return .zero
        }

        if payload.coin.chainType == .EVM {
            let gas = payload.chainSpecific.gas

            guard let weiPerGWeiDecimal = Decimal(string: EVMHelper.weiPerGWei.description),
                  let gasDecimal = Decimal(string: gas.description) else {
                return .empty
            }

            let gasGwei = gasDecimal / weiPerGWeiDecimal
            let gasInReadable = gasGwei.formatToDecimal(digits: nativeToken.decimals)

            var feeInReadable = feesInReadable(coin: payload.coin, fee: payload.chainSpecific.fee)
            feeInReadable = feeInReadable.nilIfEmpty.map { " (~\($0))" } ?? ""

            return "\(gasInReadable) \(payload.coin.chain.feeUnit)\(feeInReadable)"
        }

        let gasAmount = Decimal(payload.chainSpecific.gas) / pow(10, nativeToken.decimals)
        let gasInReadable = gasAmount.formatToDecimal(digits: nativeToken.decimals)

        var feeInReadable = feesInReadable(coin: payload.coin, fee: payload.chainSpecific.gas)
        feeInReadable = feeInReadable.nilIfEmpty.map { " (~\($0))" } ?? ""

        return "\(gasInReadable) \(payload.coin.chain.feeUnit)\(feeInReadable)"
    }
    
    func getProvider() -> String {
        switch keysignPayload?.swapPayload {
        case .oneInch:
            return "1Inch"
        case .kyberSwap:
            return "KyberSwap"
        case .thorchain:
            return "THORChain"
        case .mayachain:
            return "Maya protocol"
        case .none:
            return .empty
        }
    }
    
    func feesInReadable(coin: Coin, fee: BigInt) -> String {
        var nativeCoinAux: Coin?
        
        if coin.isNativeToken {
            nativeCoinAux = coin
        } else {
            nativeCoinAux = ApplicationState.shared.currentVault?.coins.first(where: { $0.chain == coin.chain && $0.isNativeToken })
        }
        
        guard let nativeCoin = nativeCoinAux else {
            return ""
        }
        
        let fee = nativeCoin.decimal(for: fee)
        return RateProvider.shared.fiatBalanceString(value: fee, coin: nativeCoin)
    }
    
    func getFromAmount() -> String {
        guard let payload = keysignPayload?.swapPayload else { return .empty }
        let amount = payload.fromCoin.decimal(for: payload.fromAmount)
        return "\(amount.formatDecimalToLocale()) \(payload.fromCoin.ticker)"
    }

    func getToAmount() -> String {
        guard let payload = keysignPayload?.swapPayload else { return .empty }
        let amount = payload.toAmountDecimal
        return "\(amount.formatDecimalToLocale()) \(payload.toCoin.ticker)"
        
    }
}
