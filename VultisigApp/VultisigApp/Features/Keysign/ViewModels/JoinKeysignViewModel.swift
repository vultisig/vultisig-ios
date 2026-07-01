//
//  JoinKeysignViewModel.swift
//  VultisigApp
//

import Foundation
import OSLog
import BigInt
import SwiftData
import SwiftUI

private typealias ContractCallHeroDisplay = (
    display: String,
    amountText: String,
    ticker: String,
    logo: String,
    /// True when the amount is a MAX_UINT256 sentinel that we're labeling
    /// "Unlimited". The UI should highlight this as a warning since granting
    /// unlimited approval is the riskiest case an unsuspecting user can sign.
    isUnlimited: Bool
)

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
    /// Multi-round QBTC claim — driven by `qbtcClaimDriver` rather than
    /// the standard single-keysign flow. Set when the scanned QR has
    /// `isQbtcClaim == true`. See [[v2-secure-vault-design]].
    case QBTCClaim
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
    @Published var isJoiningCommittee = false
    @Published var keysignPayload: KeysignPayload? = nil
    /// Set when the scanned QR has `isQbtcClaim == true`. The standard
    /// single-keysign flow steps aside while this driver runs the
    /// peer-side flow. See [[v2-secure-vault-design]].
    @Published var qbtcClaimDriver: QBTCClaimJoinDriver? = nil
    @Published var customMessagePayload: CustomMessagePayload? = nil
    @Published var serviceName = ""
    @Published var serverAddress: String? = nil
    @Published var useVultisigRelay = false
    @Published var isCameraPermissionGranted: Bool? = nil

    @Published var decodedMemo: String?
    @Published var decodedFunctionSignature: String?
    @Published var decodedFunctionArguments: String?
    @Published var decodedFunctionName: String?
    @Published var decodedTokenDisplay: String?
    @Published var decodedTokenIsUnlimited: Bool = false
    @Published var decodedTokenAmount: String?
    @Published var decodedTokenTicker: String?
    @Published var decodedTokenLogo: String?
    @Published var decodedTokenFiat: String?
    @Published var blockaidSimulation: BlockaidSimulationInfo?
    @Published var securityScannerState: SecurityScannerState = .idle
    @Published var didLoadSimulation: Bool = false

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
    private let swapFeeViewModel = JoinKeysignSwapFeeViewModel()

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
        guard !isJoiningCommittee else { return }

        guard let serverURL = serverAddress else {
            return logger.error("Server URL could not be found. Please ensure you're connected to the correct network.")
        }
        guard !sessionID.isEmpty else {
            return logger.error("Session ID has not been acquired. Please scan the QR code again.")
        }

        isJoiningCommittee = true
        Utils.sendRequest(
            urlString: "\(serverURL)/\(sessionID)",
            method: "POST",
            headers: nil,
            body: [localPartyID]
        ) { success in
            DispatchQueue.main.async {
                self.isJoiningCommittee = false
                if success {
                    self.logger.info("Successfully joined the keysign committee.")
                    self.status = .WaitingForKeysignToStart
                } else {
                    self.errorMsg = "joinKeysignCommitteeFailed".localized
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
                        self.errorMsg = "keysignStartResponseError".localized
                        self.status = .FailedToStart
                    }
                }
            case .failure(let error):
                let err = error as NSError
                if err.code == 404 {
                    self.logger.info("Waiting for keysign to start. Please stand by.")
                } else {
                    DispatchQueue.main.async {
                        self.errorMsg = String(format: "keysignStartVerifyFailed".localized, error.localizedDescription)
                        self.status = .FailedToStart
                    }
                }
            }
        })
    }

    func prepareKeysignMessages(keysignPayload: KeysignPayload) async {
        // QBTC claim payloads are flagged with `isQbtcClaim` and don't have
        // a standard tx body; the QBTCClaimJoinDriver computes the round-1
        // message hash itself. Skip the standard factory so it doesn't
        // fail trying to build sighashes from a body that isn't there.
        if keysignPayload.isQbtcClaim {
            guard QBTCConfig.isFeatureEnabled else {
                self.errorMsg = "qbtcClaimDisabledFromAdvanced".localized
                self.status = .FailedToStart
                return
            }
            return
        }
        // The proto UTXOSpecific can't carry the live ZEC branch id, so a
        // payload rebuilt from the initiator's QR/relay proto arrives with it
        // nil. Re-resolve the same network-global value the initiator used
        // before computing sighashes so this co-signer's ZIP-243 digest matches
        // the rest of the committee.
        let keysignPayload = await withZcashBranchId(keysignPayload)
        self.keysignPayload = keysignPayload
        do {
            let keysignFactory = KeysignMessageFactory(payload: keysignPayload)
            let preSignedImageHash = try keysignFactory.getKeysignMessages()
            self.logger.info("Successfully prepared messages for keysigning.")
            self.keysignMessages = preSignedImageHash.sorted()
            if self.keysignMessages.isEmpty {
                self.errorMsg = "noMessagesToSign".localized
                self.status = .FailedToStart
            }
        } catch {
            self.errorMsg = String(format: "prepareKeysignMessagesFailed".localized, error.localizedDescription)
            self.status = .FailedToStart
        }
    }

    func prepareKeysignMessages(customMessagePayload: CustomMessagePayload) {
        self.keysignMessages = customMessagePayload.keysignMessages
    }

    /// Re-stamps the live ZIP-243 branch id onto a Zcash UTXO payload rebuilt
    /// from proto. Returns the payload unchanged for non-Zcash chains, non-UTXO
    /// specifics, or when the RPC is unreachable (the signing helpers then
    /// refuse rather than sign with a stale id).
    private func withZcashBranchId(_ payload: KeysignPayload) async -> KeysignPayload {
        guard payload.coin.chain == .zcash,
              case .UTXO(let byteFee, let sendMaxAmount, _) = payload.chainSpecific,
              let branchId = await ZcashService.shared.getConsensusBranchIdHex() else {
            return payload
        }
        return payload.withChainSpecific(.UTXO(byteFee: byteFee, sendMaxAmount: sendMaxAmount, zcashBranchId: branchId))
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
                await self.prepareKeysignMessages(keysignPayload: payload)
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

            // QBTC claim fork — if the loaded payload is flagged with
            // `isQbtcClaim`, hand off to the QBTC-claim peer driver and
            // step the standard single-keysign flow aside. Reads from
            // `self.keysignPayload` so it covers both inline payloads and
            // ones fetched from the relay via `ensureKeysignPayload`.
            // Post-qbtc#158 the peer only runs one BTC ECDSA round; the
            // session is the keysign message's own session, not a
            // round-suffixed derivation of a base session. The peer
            // derives the claimer's QBTC address from its own vault.
            if let payload = self.keysignPayload, payload.isQbtcClaim {
                guard QBTCConfig.isFeatureEnabled else {
                    self.errorMsg = "qbtcClaimDisabledFromAdvanced".localized
                    self.status = .FailedToStart
                    return
                }
                let session = KeysignSessionInfo(
                    sessionId: keysignMsg.sessionID,
                    encryptionKeyHex: keysignMsg.encryptionKeyHex,
                    serviceName: keysignMsg.serviceName,
                    localPartyId: self.localPartyID,
                    serverAddr: Endpoint.vultisigRelay
                )
                let driver = QBTCClaimJoinDriver(
                    vault: self.vault,
                    session: session
                )
                self.qbtcClaimDriver = driver
                self.status = .QBTCClaim
                Task { await driver.run() }
            }
        } catch {
            self.errorMsg = String(format: "decodeKeysignMessageError".localized, error.localizedDescription)
            self.status = .FailedToStart
        }
    }

    func manageQrCodeStates() {
        // QBTC claim flow drives its own status transitions via
        // `qbtcClaimDriver.phase`; don't let the standard flow override.
        if status == .QBTCClaim {
            return
        }
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
            await self.prepareKeysignMessages(keysignPayload: kp)
        } catch {
            self.errorMsg = String(format: "decodeKeysignMessageError".localized, error.localizedDescription)
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
            self.errorMsg = String(format: "decodeCustomMessagePayloadError".localized, error.localizedDescription)
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
        // TON path: TonConnect bodies don't carry an EVM-style 4byte memo, so
        // skip the EVM decoder entirely and surface a jetton hero straight
        // from the BOC payloads. Hero appears only when we can resolve the
        // jetton's display metadata from the active vault.
        if resolvedContractCallChain() == .ton,
           let messages = keysignPayload?.signTon?.tonMessages, !messages.isEmpty {
            let display = TonOperationExtractor.extract(messages: messages, vault: vault)
            self.decodedTokenDisplay = display?.display
            self.decodedTokenAmount = display?.amountText
            self.decodedTokenTicker = display?.ticker
            self.decodedTokenLogo = display?.logo
            self.decodedTokenFiat = display?.fiat
            self.decodedTokenIsUnlimited = false
            return
        }

        let candidates = [keysignPayload?.memo, customMessagePayload?.message]
        guard let memo = candidates.compactMap({ $0 }).first(where: { !$0.isEmpty }) else {
            return
        }

        // 1. Attempt to get structured parameters (Generic 4byte path)
        var parsedParams: ParsedMemoParams? = nil
        let isEvm = resolvedContractCallChain()?.chainType == .EVM
        if isEvm, memo.hasPrefix("0x") {
             parsedParams = await MemoDecodingService.shared.getParsedMemo(memo: memo)
        }

        // 2. Get the full string representation from the existing extension service
        // This handles known selectors (Transfer, Approve), Kyber, etc.
        let extensionDecoded = await memo.decodedExtensionMemoAsync()

        let functionName = parsedParams.flatMap {
            ContractCallExtractor.evmFunctionName(from: $0.functionSignature)
        }.map(capitalizeFirstCharacter)
        let resolvedTokenDisplay = await resolveTokenDisplay(parsedParams: parsedParams)

        DispatchQueue.main.async {
            // Default to showing the extension decoded string as the Memo
            self.decodedMemo = extensionDecoded
            self.decodedFunctionName = functionName
            self.decodedTokenDisplay = resolvedTokenDisplay?.display
            self.decodedTokenAmount = resolvedTokenDisplay?.amountText
            self.decodedTokenTicker = resolvedTokenDisplay?.ticker
            self.decodedTokenLogo = resolvedTokenDisplay?.logo
            self.decodedTokenIsUnlimited = resolvedTokenDisplay?.isUnlimited ?? false

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

    private func resolveTokenDisplay(
        parsedParams: ParsedMemoParams?
    ) async -> ContractCallHeroDisplay? {
        guard let params = parsedParams else { return nil }
        guard let pair = ContractCallExtractor.extract(
            signature: params.functionSignature,
            argsJson: params.functionArguments,
            toAddress: keysignPayload?.toAddress
        ) else { return nil }

        guard let chain = resolvedContractCallChain() else { return nil }
        let addressLower = pair.tokenAddress.lowercased()

        // Check vault first (user has added it), then built-in tokens registry, then a
        // live `eth_call` against the contract for unknown tokens.
        let ticker: String
        let decimals: Int
        let logo: String
        if let vaultMatch = vault.coins.first(where: {
            $0.chain == chain && $0.contractAddress.lowercased() == addressLower
        }) {
            ticker = vaultMatch.ticker
            decimals = vaultMatch.decimals
            logo = vaultMatch.logo
        } else if let builtIn = TokensStore.findTokenMeta(
            chain: chain,
            contractAddress: pair.tokenAddress
        ) {
            ticker = builtIn.ticker
            decimals = builtIn.decimals
            logo = builtIn.logo
        } else if let resolved = await TokenMetadataResolver.shared.resolve(
            contractAddress: pair.tokenAddress,
            on: chain
        ) {
            ticker = resolved.symbol
            decimals = resolved.decimals
            logo = "" // No logo asset for resolved-only tokens; the user can add to vault to attach one.
        } else {
            return nil
        }

        guard let amount = BigInt(pair.rawAmount) else { return nil }

        // MAX_UINT256 is a sentinel. For approvals → "Unlimited". For withdraw/repay
        // the exact amount depends on on-chain state — return nil (skip display).
        if pair.rawAmount == ContractCallExtractor.maxUInt256Decimal,
           let funcName = ContractCallExtractor.evmFunctionName(from: params.functionSignature) {
            guard let label = ContractCallExtractor.sentinelLabelFor(funcName: funcName) else { return nil }
            return (
                display: "\(label) \(ticker)",
                amountText: label,
                ticker: ticker,
                logo: logo,
                isUnlimited: true
            )
        }

        let divisor = BigInt(10).power(decimals)
        let whole = amount / divisor
        let remainder = amount % divisor
        let formatted: String
        if remainder == 0 {
            formatted = "\(whole)"
        } else {
            let remainderStr = String(remainder)
            let padded = String(repeating: "0", count: max(0, decimals - remainderStr.count)) + remainderStr
            var trimmed = padded
            while trimmed.hasSuffix("0") {
                trimmed.removeLast()
            }
            formatted = trimmed.isEmpty ? "\(whole)" : "\(whole).\(trimmed)"
        }
        return (
            display: "\(formatted) \(ticker)",
            amountText: formatted,
            ticker: ticker,
            logo: logo,
            isUnlimited: false
        )
    }

    private func resolvedContractCallChain() -> Chain? {
        if let chain = keysignPayload?.coin.chain {
            return chain
        }

        guard let chainValue = customMessagePayload?.chain, !chainValue.isEmpty else {
            return nil
        }

        return Chain(rawValue: chainValue) ?? Chain(name: chainValue)
    }

    private func capitalizeFirstCharacter(_ value: String) -> String {
        guard let first = value.first else { return value }
        return first.uppercased() + value.dropFirst()
    }

    func loadSimulation() async {
        guard let payload = keysignPayload else {
            didLoadSimulation = true
            return
        }
        securityScannerState = .scanning
        let result = await BlockaidSimulationService.shared.scan(keysignPayload: payload)
        blockaidSimulation = result.simulation
        if let scannerResult = result.scannerResult {
            securityScannerState = .scanned(scannerResult)
        } else {
            securityScannerState = .idle
        }
        didLoadSimulation = true
    }

    /// The hero displayed above the transaction summary. Promotes a resolved
    /// Blockaid balance change when available, falls back to a title-only
    /// display with an "unverified function" caption for 4byte-only decodes.
    var heroContent: HeroContent? {
        if let sim = blockaidSimulation {
            switch sim {
            case .transfer(let coin, _):
                return .send(
                    title: decodedFunctionName,
                    coin: HeroCoinAmount(
                        amount: sim.heroAmountText,
                        ticker: coin.ticker,
                        logo: coin.logo,
                        fiat: heroCoinFiat(chain: coin.chain, address: coin.address, amount: sim.fromAmountDecimal)
                    )
                )
            case .swap(let from, let to, _, _):
                return .swap(
                    title: decodedFunctionName,
                    from: HeroCoinAmount(
                        amount: sim.heroAmountText,
                        ticker: from.ticker,
                        logo: from.logo,
                        fiat: heroCoinFiat(chain: from.chain, address: from.address, amount: sim.fromAmountDecimal)
                    ),
                    to: HeroCoinAmount(
                        amount: sim.heroToAmountText ?? "",
                        ticker: to.ticker,
                        logo: to.logo,
                        fiat: heroCoinFiat(chain: to.chain, address: to.address, amount: sim.toAmountDecimal ?? .zero)
                    )
                )
            }
        }

        // TON-side fallback: when the BOC decoder resolved a jetton hero we
        // surface it directly, even though Blockaid never simulates TON.
        if let amount = decodedTokenAmount,
           let ticker = decodedTokenTicker,
           let logo = decodedTokenLogo,
           !amount.isEmpty {
            return .send(
                title: decodedFunctionName,
                coin: HeroCoinAmount(amount: amount, ticker: ticker, logo: logo, fiat: decodedTokenFiat)
            )
        }

        if didLoadSimulation,
           blockaidSimulation == nil,
           let name = decodedFunctionName {
            return .title(text: name, caption: "unverifiedFunction".localized)
        }
        return nil
    }

    var providerName: String {
        keysignPayload?.swapPayload?.providerName ?? .empty
    }

    /// dApp identity (name / url / icon) attached to the keysign request, if
    /// any. Used by `DAppRequestBanner` on the verify and done screens. Empty
    /// metadata is treated as absent.
    var dappMetadata: DAppMetadata? {
        keysignPayload?.dappMetadata
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

    /// Swap-fee row for the swap confirm screen, nil when the payload
    /// carries no fee or no trustworthy coin context (legacy sender).
    func getSwapFee() -> (feeCrypto: String, feeFiat: String)? {
        swapFeeViewModel.getSwapFee(swapPayload: keysignPayload?.swapPayload, vault: vault)
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

    /// Fiat value of a plain send amount for the verify header, mirroring the
    /// swap `getFromFiatAmount()` and sharing the fee's `RateProvider` price
    /// source (`Coin.fiat(decimal:)`). Returns empty for swaps (fiat is carried
    /// on the hero from/to rows), for contract-call / approval decodes (the
    /// amount row shows a decoded token, not a coin transfer), for zero-value
    /// sends, or when no rate is available — so nothing misleading renders.
    func getAmountFiat() -> String {
        guard let payload = keysignPayload else { return .empty }
        guard payload.swapPayload == nil,
              decodedTokenDisplay == nil,
              payload.toAmount > 0,
              RateProvider.shared.hasRate(for: payload.coin) else {
            return .empty
        }
        return payload.coin.fiat(decimal: payload.toAmountDecimal)
            .formatToFiat(includeCurrencySymbol: true)
    }

    /// Best-effort fiat for a hero coin row, resolved against the active vault
    /// so it shares the amount/fee `RateProvider` price source. Matches the
    /// simulated coin by chain + contract address (native when `address` is
    /// nil/empty). Returns `nil` when the coin isn't in the vault or has no
    /// rate, so the hero simply omits the fiat sub-line.
    private func heroCoinFiat(chain: Chain, address: String?, amount: Decimal) -> String? {
        let normalizedAddress = address?.lowercased()
        let match = vault.coins.first { coin in
            guard coin.chain == chain else { return false }
            if let normalizedAddress, !normalizedAddress.isEmpty {
                return coin.contractAddress.lowercased() == normalizedAddress
            }
            return coin.isNativeToken
        }
        guard let match, RateProvider.shared.hasRate(for: match) else { return nil }
        let fiat = match.fiat(decimal: amount).formatToFiat(includeCurrencySymbol: true)
        return fiat.isEmpty ? nil : fiat
    }

}
