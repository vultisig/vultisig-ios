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
    @Published var decodedFunctionSignature: String?
    @Published var decodedFunctionArguments: String?

    var encryptionKeyHex: String = ""
    var payloadID: String = ""
    var customPayloadID: String = ""

    var memo: String? {
        guard let decodedMemo = decodedMemo, !decodedMemo.isEmpty else {
            return keysignPayload?.memo
        }

        return decodedMemo
    }

    private let gasViewModel = JoinKeysignGasViewModel()

    init() {
        self.vault = Vault(name: "Main Vault")
        self.isShowingScanner = false
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
            headers: nil,
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
                         headers: nil,
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
                    DispatchQueue.main.async {
                        self.errorMsg = "Failed to verify keysign start. Error: \(error.localizedDescription)"
                        self.status = .FailedToStart
                    }
                }
            }
        })
    }

    func prepareKeysignMessages(keysignPayload: KeysignPayload) {
        do {
            let keysignFactory = KeysignMessageFactory(payload: keysignPayload)
            let preSignedImageHash = try keysignFactory.getKeysignMessages()
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

            var vaultPublicKeyECDSAInQrCode: String = .empty

            if let keysignPayload = keysignMsg.payload {
                vaultPublicKeyECDSAInQrCode = keysignPayload.vaultPubKeyECDSA
            }
            if let payload = keysignMsg.payload {
                self.prepareKeysignMessages(keysignPayload: payload)
            }
            if let payload = keysignMsg.customMessagePayload {
                self.prepareKeysignMessages(customMessagePayload: payload)
            }

            self.payloadID = keysignMsg.payloadID
            self.customPayloadID = keysignMsg.customPayloadID
            self.useVultisigRelay = keysignMsg.useVultisigRelay

            if useVultisigRelay {
                self.serverAddress = Endpoint.vultisigRelay
            }

            await ensureKeysignPayload()
            await ensureCustomMessagePayload()
            // Decode custom message if present
            if let customMessage = customMessagePayload {
                self.customMessagePayload?.decodedMessage = await CustomMessageDecoder.decode(customMessage)
                if customMessage.vaultPublicKeyECDSA != .empty {
                    vaultPublicKeyECDSAInQrCode = customMessage.vaultPublicKeyECDSA
                }
            }
            // Auto-select correct vault BEFORE preparing messages
            if vaultPublicKeyECDSAInQrCode != .empty && vault.pubKeyECDSA != vaultPublicKeyECDSAInQrCode {
                if let correctVault = fetchVaults().first(where: { $0.pubKeyECDSA == vaultPublicKeyECDSAInQrCode }),
                   !correctVault.localPartyID.isEmpty {
                    self.vault = correctVault
                    self.localPartyID = correctVault.localPartyID
                    // Update AppViewModel so fee calculations can access the correct vault
                    AppViewModel.shared.set(selectedVault: correctVault)
                    logger.info("Auto-selected correct vault: \(correctVault.name) with pubKey: \(correctVault.pubKeyECDSA)")
                }
            }
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

    func ensureKeysignPayload() async {
        if self.payloadID.isEmpty || self.keysignPayload != nil {
            return
        }
        guard let serverAddress else {
            return
        }

        let payloadService = PayloadService(serverURL: serverAddress)
        do {
            let payload = try await payloadService.getPayload(hash: self.payloadID)
            let kp: KeysignPayload = try ProtoSerializer.deserialize(base64EncodedString: payload)
            self.keysignPayload = kp
            self.prepareKeysignMessages(keysignPayload: kp)
        } catch {
            self.errorMsg = "Error decoding keysign message: \(error.localizedDescription)"
            self.status = .FailedToStart
        }
    }

    func ensureCustomMessagePayload() async {
        if self.customPayloadID.isEmpty || self.customMessagePayload != nil {
            return
        }
        guard let serverAddress else {
            return
        }

        let payloadService = PayloadService(serverURL: serverAddress)
        do {
            let payload = try await payloadService.getPayload(hash: self.customPayloadID)
            let cmp: CustomMessagePayload = try ProtoSerializer.deserialize(base64EncodedString: payload)
            self.customMessagePayload = cmp
            self.prepareKeysignMessages(customMessagePayload: cmp)
        } catch {
            self.errorMsg = "Error decoding custom message payload: \(error.localizedDescription)"
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
        Task {
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
            logger.error("fail to get thorchain network id, \(error.localizedDescription)")
        }
    }

    func loadFunctionName() async {
        guard let memo = keysignPayload?.memo, !memo.isEmpty else {
            return
        }

        // 1. Attempt to get structured parameters (Generic 4byte path)
        var parsedParams: ParsedMemoParams? = nil
        if keysignPayload?.coin.chainType == .EVM, memo.hasPrefix("0x") {
             parsedParams = await MemoDecodingService.shared.getParsedMemo(memo: memo)
        }

        // 2. Get the full string representation from the existing extension service
        // This handles known selectors (Transfer, Approve), Kyber, etc.
        let extensionDecoded = await memo.decodedExtensionMemoAsync()

        DispatchQueue.main.async {
            // Default to showing the extension decoded string as the Memo
            self.decodedMemo = extensionDecoded

            // 3. Decide if we should show the enhanced Split View (Signature + Arguments)
            if let p = parsedParams, let extStr = extensionDecoded {
                // Heuristic: If the extension string contains "Parameters:", it likely came from
                // the generic fallback logic in String+ExtensionMemo.swift.
                // In this case, we prefer the native Split View with Turquoise text.
                if extStr.contains("Parameters:") {
                    self.decodedFunctionSignature = p.functionSignature
                    self.decodedFunctionArguments = p.functionArguments
                } else {
                    // It's a "Known Selector" or "Custom Action" (e.g. "Transfer Token").
                    // Keep the text-based Memo view to preserve user-friendly naming.
                    self.decodedFunctionSignature = nil
                    self.decodedFunctionArguments = nil
                }
            } else if let p = parsedParams {
                // We have structured params but no extension string (unlikely, but fallback)
                // Use split view
                self.decodedFunctionSignature = p.functionSignature
                self.decodedFunctionArguments = p.functionArguments
                self.decodedMemo = p.functionSignature // fallback title
            } else {
                // No structured params, strict fallback
                self.decodedFunctionSignature = nil
                self.decodedFunctionArguments = nil
            }
        }
    }

    var providerName: String {
        keysignPayload?.swapPayload?.providerName ?? .empty
    }

    func getFromAmount() -> String {
        guard let payload = keysignPayload?.swapPayload else { return .empty }
        let amount = payload.fromCoin.decimal(for: payload.fromAmount)
        return "\(amount.formatForDisplay()) \(payload.fromCoin.ticker)"
    }

    func getToAmount() -> String {
        guard let payload = keysignPayload?.swapPayload else { return .empty }
        let amount = payload.toAmountDecimal
        return "\(amount.formatForDisplay()) \(payload.toCoin.ticker)"

    }

    func getCalculatedNetworkFee() -> (feeCrypto: String, feeFiat: String) {
        guard let keysignPayload else { return (.empty, .empty) }
        return gasViewModel.getCalculatedNetworkFee(payload: keysignPayload)
    }

    func getFromFiatAmount() -> String {
        guard let payload = keysignPayload?.swapPayload else { return .empty }
        let amount = payload.fromCoin.decimal(for: payload.fromAmount)
        let fiatDecimal = payload.fromCoin.fiat(decimal: amount)
        return fiatDecimal.formatToFiat(includeCurrencySymbol: true)
    }

    func getToFiatAmount() -> String {
        guard let payload = keysignPayload?.swapPayload else { return .empty }
        let fiatDecimal = payload.toCoin.fiat(decimal: payload.toAmountDecimal)
        return fiatDecimal.formatToFiat(includeCurrencySymbol: true)
    }

}
