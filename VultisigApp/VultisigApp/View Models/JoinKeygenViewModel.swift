//
//  JoinKeygenViewModel.swift
//  VultisigApp
//
//  Created by Johnny Luo on 18/3/2024.
//

import Foundation
import OSLog

import CoreImage
import Vision

enum JoinKeygenStatus {
    case DiscoverSessionID
    case DiscoverService
    case JoinKeygen
    case WaitingForKeygenToStart
    case KeygenStarted
    case FailToStart
    case NoCameraAccess
}

@MainActor
class JoinKeygenViewModel: ObservableObject {
    private let logger = Logger(subsystem: "join-keygen", category: "viewmodel")
    var vault: Vault
    var serviceDelegate: ServiceDelegate?

    private var keyImportChains: [Chain] = []
    var keyImportInput: KeyImportInput? {
        guard tssType == .KeyImport else { return nil }
        // Joining device doesn't have the mnemonic, so derivation is determined by initiating device
        // Create chain settings with default derivation (actual derivation comes from initiating device)
        let chainSettings = keyImportChains.map { ChainImportSetting(chain: $0) }
        return KeyImportInput(mnemonic: "", chainSettings: chainSettings)
    }

    @Published var tssType: TssType = .Keygen
    @Published var isShowingScanner = false
    @Published var sessionID: String? = nil
    @Published var hexChainCode: String = ""
    @Published var isCameraPermissionGranted: Bool? = nil
    @Published var selectedVault: Vault? = nil
    @Published var areVaultsMismatched: Bool = false

    @Published var netService: NetService? = nil
    @Published var status = JoinKeygenStatus.DiscoverSessionID
    @Published var keygenCommittee = [String]()
    @Published var oldCommittee = [String]()
    @Published var localPartyID: String = ""
    @Published var serviceName = ""
    @Published var error: JoinKeygenError? = nil
    @Published var serverAddress: String? = nil
    @Published var oldResharePrefix: String = ""

    var encryptionKeyHex: String = ""
    var vaults: [Vault] = []

    init() {
        self.vault = Vault(name: "Main Vault")
    }

    func setData(
        vault: Vault,
        selectedVault: Vault?,
        serviceDelegate: ServiceDelegate,
        vaults: [Vault],
        isCameraPermissionGranted: Bool
    ) {
        self.vault = vault
        self.selectedVault = selectedVault
        self.vaults = vaults
        self.serviceDelegate = serviceDelegate
        self.isCameraPermissionGranted = isCameraPermissionGranted

        if !vault.localPartyID.isEmpty {
            self.localPartyID = vault.localPartyID
        } else {
            self.localPartyID = Utils.getLocalDeviceIdentity()
            vault.localPartyID = self.localPartyID
        }

        if let isAllowed = self.isCameraPermissionGranted, !isAllowed {
            status = .NoCameraAccess
        }
    }

    func showBarcodeScanner() {
        isShowingScanner = true
    }

    func setStatus(status: JoinKeygenStatus) {
        self.status = status
    }

    func discoverService() {
        self.netService = NetService(domain: "local.", type: "_http._tcp.", name: self.serviceName)
        netService?.delegate = self.serviceDelegate
        netService?.resolve(withTimeout: 10)
    }

    func joinKeygenCommittee() {
        guard let serverURL = serverAddress, let sessionID = sessionID else {
            logger.error("Required information for joining key generation committee is missing.")
            return
        }

        let urlString = "\(serverURL)/\(sessionID)"
        let body = [localPartyID]
        Utils.sendRequest(urlString: urlString,
                          method: "POST",
                          headers: nil,
                          body: body) { success in
            if success {
                self.logger.info("Successfully joined the key generation committee.")
                DispatchQueue.main.async {
                    self.status = .WaitingForKeygenToStart
                }
            } else {
                self.logger.error("Failed to join the key generation committee.")
            }
        }
    }
    func stopJoinKeygen() {
        self.status = .DiscoverService
    }
    func waitForKeygenStart() async {
        do {
            let t = Task {
                repeat {
                    try await checkKeygenStarted()
                    try await Task.sleep(for: .seconds(1))
                } while self.status == .WaitingForKeygenToStart
            }
            try await t.value
        } catch {
            logger.error("Failed to wait for keygen to start. Error: \(error.localizedDescription)")
        }
    }
    /// Checks if the key generation process has started by querying the server.
    /// - Throws: `HelperError.runtimeError` if required information is missing or the URL is invalid.
    ///           Any error thrown by `URLSession` or JSON decoding.
    /// - Note: Updates the `keygenCommittee` and `status` on the main thread if the process has started.
    /// - Returns: Nothing. Updates state via side effects.
    private func checkKeygenStarted() async throws {
        guard let serverURL = serverAddress, let sessionID = sessionID else {
            throw HelperError.runtimeError("Required information for checking key generation status is missing.")
        }

        let urlString = "\(serverURL)/start/\(sessionID)"
        guard let url = URL(string: urlString) else {
            throw HelperError.runtimeError("Invalid URL: \(urlString)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, resp) = try await URLSession.shared.data(for: request)
        guard let httpResponse = resp as? HTTPURLResponse else {
            self.logger.error("Invalid response from server")
            return
        }
        switch httpResponse.statusCode {
        case 200 ... 299:
            if data.isEmpty {
                self.logger.debug("Key generation not started yet (empty body)")
                return
            }
            do {
                let decoder = JSONDecoder()
                let peers = try decoder.decode([String].self, from: data)
                DispatchQueue.main.async {
                    if peers.contains(self.localPartyID) {
                        // Trust the server's authoritative list order.
                        self.keygenCommittee = peers
                        self.status = .KeygenStarted
                    }
                }
            } catch {
                self.logger.error("Failed to decode response to JSON: \(String(data: data, encoding: .utf8) ?? "N/A") , error: \(error.localizedDescription)")
            }
        case 404:
            // keygen not started yet
            self.logger.debug("Key generation not started yet (404)")
        default:
            self.logger.error("Server returned status code \(httpResponse.statusCode)")
        }
    }

    func isVaultNameAlreadyExist(name: String) -> Bool {
        for v in self.vaults {
            if v.name == name && !v.pubKeyECDSA.isEmpty {
                return true
            }
        }
        return false
    }

    func handleQrCodeSuccessResult(scanData: String, tssType: TssType) {
        self.tssType = tssType

        var useVultisigRelay = false
        do {
            switch tssType {
            case .Keygen, .KeyImport:
                let keygenMsg: KeygenMessage = try ProtoSerializer.deserialize(
                    base64EncodedString: scanData)
                sessionID = keygenMsg.sessionID
                hexChainCode = keygenMsg.hexChainCode
                vault.hexChainCode = hexChainCode
                serviceName = keygenMsg.serviceName
                encryptionKeyHex = keygenMsg.encryptionKeyHex
                useVultisigRelay = keygenMsg.useVultisigRelay
                vault.name = keygenMsg.vaultName
                vault.libType = keygenMsg.libType
                keyImportChains = keygenMsg.chains
                if isVaultNameAlreadyExist(name: keygenMsg.vaultName) {
                    error = .vaultNameAlreadyExists
                    logger.error("Vault name already exists: \(keygenMsg.vaultName)")
                    status = .FailToStart
                    return
                }
            case .Reshare, .Migrate:
                let reshareMsg: ReshareMessage = try ProtoSerializer.deserialize(
                    base64EncodedString: scanData)
                oldCommittee = reshareMsg.oldParties
                sessionID = reshareMsg.sessionID
                hexChainCode = reshareMsg.hexChainCode
                serviceName = reshareMsg.serviceName
                encryptionKeyHex = reshareMsg.encryptionKeyHex
                useVultisigRelay = reshareMsg.useVultisigRelay
                oldResharePrefix = reshareMsg.oldResharePrefix

                if tssType == .Migrate {
                    // this logic only applies to migrate
                    guard let selectedVaultKey = selectedVault?.pubKeyECDSA, selectedVaultKey == reshareMsg.pubKeyECDSA else {
                        areVaultsMismatched = true
                        return
                    }
                }

                // this means the vault is new , and it join the reshare to become the new committee
                if vault.pubKeyECDSA.isEmpty {
                    if !reshareMsg.pubKeyECDSA.isEmpty {
                        if let reshareVault = vaults.first(where: { $0.pubKeyECDSA == reshareMsg.pubKeyECDSA }) {
                            self.vault = reshareVault
                            self.localPartyID = reshareVault.localPartyID
                        } else {
                            vault.hexChainCode = reshareMsg.hexChainCode
                            vault.libType = reshareMsg.libType
                            vault.name = reshareMsg.vaultName
                            if isVaultNameAlreadyExist(name: reshareMsg.vaultName) {
                                error = .vaultNameAlreadyExists
                                logger.error("Vault name already exists: \(reshareMsg.vaultName)")
                                status = .FailToStart
                                return
                            }
                        }
                    }

                } else {
                    if vault.pubKeyECDSA != reshareMsg.pubKeyECDSA {
                        error = .wrongVaultSelected
                        logger.error("The vault's public key doesn't match the reshare message's public key")
                        status = .FailToStart
                        return
                    }
                    if vault.libType != reshareMsg.libType {
                        error = .vaultTypeMismatch
                        status = .FailToStart
                        return
                    }
                }
            }

        } catch {
            self.error = .failedToDecodeMessage(error.localizedDescription)
            status = .FailToStart
            return
        }
        if useVultisigRelay {
            self.serverAddress = Endpoint.vultisigRelay
            status = .JoinKeygen
        } else {
            status = .DiscoverService
        }
    }

    func handleQrCodeFromImage(result: Result<[URL], Error>) {
        do {
            let urlData = try Utils.handleQrCodeFromImage(result: result)
            guard let urlString = String(data: urlData, encoding: .utf8) else {
                return
            }
            handleDeeplinkScan(URL(string: urlString))
        } catch {
            print(error)
        }
    }

    func handleDeeplinkScan(_ url: URL?) {
        guard let url else {
            return
        }

        guard
            let jsonData = DeeplinkViewModel.getJsonData(url),
            let tssTypeString = DeeplinkViewModel.getTssType(url),
            let tssType = TssType(rawValue: tssTypeString) else {
            status = .FailToStart
            return
        }
        handleQrCodeSuccessResult(scanData: jsonData, tssType: tssType)
    }
}

// MARK: - Error Types

enum JoinKeygenError: Error, LocalizedError {
    case vaultNameAlreadyExists
    case wrongVaultSelected
    case vaultTypeMismatch
    case failedToDecodeMessage(String)

    var errorTitle: String {
        switch self {
        case .vaultNameAlreadyExists:
            return "vaultNameAlreadyInUse".localized
        case .wrongVaultSelected:
            return "wrongVaultSelected".localized
        case .vaultTypeMismatch:
            return "vaultTypeMismatch".localized
        case .failedToDecodeMessage:
            return "failedToDecodePeerDiscoveryMessage".localized
        }
    }

    var errorDescription: String {
        switch self {
        case .vaultNameAlreadyExists:
            return "pleaseChooseDifferentVaultName".localized
        case .wrongVaultSelected:
            return "wrongVaultSelectedDescription".localized
        case .vaultTypeMismatch:
            return "vaultTypeMismatchDescription".localized
        case .failedToDecodeMessage(let details):
            return details
        }
    }
}
