//
//  KeysignViewModel.swift
//  VultisigApp
//
//  Created by Johnny Luo on 15/3/2024.
//

import Foundation
import OSLog
import Tss
import WalletCore

enum KeysignStatus {
    case CreatingInstance
    case KeysignECDSA
    case KeysignEdDSA
    case KeysignMLDSA
    case KeysignFinished
    case KeysignFailed
    case KeysignRetryRequested
    case KeysignVaultMismatch
}
enum TssKeysignError: Error {
    case keysignFail
}
@MainActor
class KeysignViewModel: ObservableObject {
    private let logger = Logger(subsystem: "keysign", category: "tss")

    @Published var status: KeysignStatus = .CreatingInstance
    @Published var keysignError: String = .empty
    @Published var signatures = [String: TssKeysignResponse]()
    @Published var dilithiumSignatures = [String: DilithiumKeysignResponse]()
    @Published var txid: String = .empty
    @Published var approveTxid: String?
    @Published var decodedMemo: String?
    @Published var decodedFunctionName: String?
    @Published var decodedTokenAmount: String?
    @Published var decodedTokenTicker: String?
    @Published var decodedTokenLogo: String?
    @Published var decodedTokenDisplay: String?
    @Published var decodedTokenIsUnlimited: Bool = false
    @Published var decodedFunctionSignature: String?
    @Published var decodedFunctionArguments: String?
    @Published var blockaidSimulation: BlockaidSimulationInfo?
    @Published var securityScannerState: SecurityScannerState = .idle
    @Published var didLoadSimulation: Bool = false
    @Published var retryReason: BroadcastRetryReason?

    private var broadcastRetryCount = 0
    private static let maxBroadcastRetries = 1

    /// Top-level timeout for a single keysign run (TSS exchange + broadcast).
    /// Underlying poll loops can stall without producing a terminal status —
    /// iOS suspending the network session in background, DKLS retry exhaustion,
    /// a peer that never sent its share — so this is the safety net that flips
    /// the UI into the retry-requested view. See vultisig-ios#4327.
    static let keysignStageTimeout: Duration = .seconds(90)

    private struct KeysignStalledError: Error {}

    private var tssService: TssServiceImpl? = nil
    private var tssMessenger: TssMessengerImpl? = nil
    private var stateAccess: LocalStateAccessorImpl? = nil
    private var messagePuller: MessagePuller? = nil

    var keysignCommittee: [String]
    var mediatorURL: String
    var sessionID: String
    var keysignType: KeyType
    var messsageToSign: [String]
    var vault: Vault
    var keysignPayload: KeysignPayload?
    var customMessagePayload: CustomMessagePayload?
    var encryptionKeyHex: String
    var isInitiateDevice: Bool

    private let gasViewModel = JoinKeysignGasViewModel()

    var showRedacted: Bool {
        txid.isEmpty && !(keysignPayload?.skipBroadcast ?? false)
    }

    var memo: String? {
        guard let decodedMemo = decodedMemo, !decodedMemo.isEmpty else {
            return keysignPayload?.memo
        }

        return decodedMemo
    }

    init() {
        self.keysignCommittee = []
        self.mediatorURL = ""
        self.sessionID = ""
        self.vault = Vault(name: "tempory")
        self.keysignType = .ECDSA
        self.messsageToSign = []
        self.keysignPayload = nil
        self.encryptionKeyHex = ""
        self.isInitiateDevice = false
    }

    func setData(keysignCommittee: [String],
                 mediatorURL: String,
                 sessionID: String,
                 keysignType: KeyType,
                 messagesToSign: [String],
                 vault: Vault,
                 keysignPayload: KeysignPayload?,
                 customMessagePayload: CustomMessagePayload?,
                 encryptionKeyHex: String,
                 isInitiateDevice: Bool
    ) async {
        self.keysignCommittee = keysignCommittee
        self.mediatorURL = mediatorURL
        self.sessionID = sessionID
        self.keysignType = keysignType
        self.messsageToSign = messagesToSign
        self.vault = vault
        self.keysignPayload = keysignPayload
        self.customMessagePayload = customMessagePayload
        self.encryptionKeyHex = encryptionKeyHex
        let isEncryptGCM = await FeatureFlagService().isFeatureEnabled(feature: .EncryptGCM)
        self.messagePuller = MessagePuller(encryptionKeyHex: encryptionKeyHex, pubKey: vault.pubKeyECDSA, encryptGCM: isEncryptGCM)
        self.isInitiateDevice = isInitiateDevice

        async let fn: Void = loadFunctionName()
        async let sim: Void = loadSimulation()
        _ = await (fn, sim)
    }

    func loadFunctionName() async {
        guard let memo = keysignPayload?.memo, !memo.isEmpty else {
            return
        }

        // First try to decode as Extension memo (works for all chains)
        if let extensionDecoded = memo.decodedExtensionMemo {
            decodedMemo = extensionDecoded
            return
        }

        // Fall back to EVM-specific decoding for EVM chains
        guard keysignPayload?.coin.chainType == .EVM else {
            return
        }

        do {
            decodedMemo = try await MemoDecodingService.shared.decode(memo: memo)
        } catch {
            logger.error("EVM memo decoding error: \(error.localizedDescription)")
        }
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
                        logo: coin.logo
                    )
                )
            case .swap(let from, let to, _, _):
                return .swap(
                    title: decodedFunctionName,
                    from: HeroCoinAmount(
                        amount: sim.heroAmountText,
                        ticker: from.ticker,
                        logo: from.logo
                    ),
                    to: HeroCoinAmount(
                        amount: sim.heroToAmountText ?? "",
                        ticker: to.ticker,
                        logo: to.logo
                    )
                )
            }
        }

        if didLoadSimulation,
           blockaidSimulation == nil,
           let name = decodedFunctionName {
            return .title(text: name, caption: "unverifiedFunction".localized)
        }
        return nil
    }

    /// dApp identity (name / url / icon) attached to the keysign request, if
    /// any. Used by `DAppRequestBanner` on the verify and done screens. Empty
    /// metadata is treated as absent.
    var dappMetadata: DAppMetadata? {
        keysignPayload?.dappMetadata
    }

    func getTransactionExplorerURL(txid: String) -> String {
        guard let keysignPayload else { return .empty }
        return ExplorerLinkBuilder.getExplorerURL(chain: keysignPayload.coin.chain, txid: txid)
    }

    func getSwapProgressURL(txid: String) -> String? {
        ExplorerLinkBuilder.progressLink(swapPayload: keysignPayload?.swapPayload, txHash: txid)
    }

    func startKeysign() async {
        do {
            // Race the keysign body against a stage-level timeout. If the body
            // wins, `group.next()` returns void and `cancelAll()` retires the
            // sleeper. If the sleeper wins, it throws `KeysignStalledError`
            // and we flip the UI into the retry-requested state below.
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { @MainActor [weak self] in
                    guard let self else { return }
                    switch self.vault.libType {
                    case .GG20, .none:
                        await self.startKeysignGG20()
                    case .DKLS:
                        await self.startKeysignDKLS(isImport: false)
                    case .KeyImport:
                        await self.startKeysignDKLS(isImport: true)
                    }
                }
                group.addTask {
                    try await Task.sleep(for: Self.keysignStageTimeout)
                    throw KeysignStalledError()
                }
                try await group.next()
                group.cancelAll()
            }
        } catch is KeysignStalledError {
            // Body task may still be running; only intervene if it hasn't
            // already reached a terminal status of its own. The existing
            // `KeysignFinished` guards in startKeysignDKLS/GG20 already refuse
            // to overwrite `KeysignRetryRequested`, so this write is sticky
            // unless the keysign actually completes and sets a txid (in which
            // case `KeysignView.onChange(of: txid)` will navigate away and the
            // retry view is torn down — the correct behaviour).
            let terminal: [KeysignStatus] = [.KeysignFinished, .KeysignFailed, .KeysignVaultMismatch, .KeysignRetryRequested]
            guard !terminal.contains(status) else { return }
            logger.warning("keysign exceeded \(Self.keysignStageTimeout, privacy: .public) stage timeout — requesting retry")
            self.retryReason = .other("KeysignStalled")
            setStatus(.KeysignRetryRequested)
        } catch {
            logger.error("keysign stage race exited unexpectedly: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Wraps `status = newStatus` with a logger marker. The investigation for
    /// vultisig-ios#4327 needs a TestFlight `os_log` capture to localise which
    /// poll loop stalls; keeping the transition trail in one place gives every
    /// status flip an `info`-level entry without scattering log lines across
    /// the file.
    private func setStatus(_ newStatus: KeysignStatus, file: String = #fileID, line: Int = #line) {
        if status != newStatus {
            logger.info("status: \(String(describing: self.status), privacy: .public) → \(String(describing: newStatus), privacy: .public) at \(file, privacy: .public):\(line, privacy: .public)")
        }
        self.status = newStatus
    }

    /// Wraps `txid = newTxid` with a logger marker. Counterpart to `setStatus`
    /// for vultisig-ios#4327 instrumentation. The hash itself is logged at
    /// `info` so it shows up in `os_log` captures the reporter shares back.
    private func setTxid(_ newTxid: String, file: String = #fileID, line: Int = #line) {
        if txid != newTxid {
            logger.info("txid set: \(newTxid, privacy: .public) at \(file, privacy: .public):\(line, privacy: .public)")
        }
        self.txid = newTxid
    }

    func startKeysignDKLS(isImport: Bool) async {
        do {
            // Check if we have either keysignPayload or customMessagePayload
            guard self.keysignPayload != nil || self.customMessagePayload != nil else {
                throw HelperError.runtimeError("keysign payload is nil")
            }
            // Determine chainPath - use keysignPayload if available, otherwise determine from customMessagePayload
            var chainPath: String
            var publicKey: String? = nil
            if let keysignPayload = self.keysignPayload {
                chainPath = keysignPayload.coin.coinType.derivationPath()
                publicKey = self.vault.chainPublicKeys.first(where: { $0.chain == keysignPayload.coin.chain })?.publicKeyHex
            } else if let customMessagePayload = self.customMessagePayload {
                var targetChain: Chain = .ethereum // Default to Ethereum
                // Get chain from customMessagePayload and use its coinType (case-insensitive match)
                if let chain = Chain.allCases.first(where: { $0.name.caseInsensitiveCompare(customMessagePayload.chain) == .orderedSame }) {
                    chainPath = chain.coinType.derivationPath()
                    targetChain = chain
                } else {
                    // Fallback to Ethereum if chain name cannot be parsed
                    chainPath = TokensStore.Token.ethereum.coinType.derivationPath()
                }
                publicKey = self.vault.chainPublicKeys.first(where: { $0.chain == targetChain })?.publicKeyHex
            } else {
                throw HelperError.runtimeError("keysign payload is nil")
            }

            if isImport {
                chainPath = ""
            }

            switch self.keysignType {
            case .ECDSA:
                status = .KeysignECDSA
                if !isImport {
                    publicKey = vault.pubKeyECDSA
                }
                let dklsKeysign = DKLSKeysign(keysignCommittee: self.keysignCommittee,
                                              mediatorURL: self.mediatorURL,
                                              sessionID: self.sessionID,
                                              messsageToSign: self.messsageToSign,
                                              vault: self.vault,
                                              encryptionKeyHex: self.encryptionKeyHex,
                                              chainPath: chainPath,
                                              isInitiateDevice: self.isInitiateDevice,
                                              publicKeyECDSA: publicKey ?? vault.pubKeyECDSA)
                try await dklsKeysign.DKLSKeysignWithRetry()
                self.signatures = dklsKeysign.getSignatures()
                if self.signatures.isEmpty {
                    throw HelperError.runtimeError("fail to sign transaction")
                }
            case .EdDSA:
                status = .KeysignEdDSA
                let schnorrKeysign = SchnorrKeysign(keysignCommittee: self.keysignCommittee,
                                                    mediatorURL: self.mediatorURL,
                                                    sessionID: self.sessionID,
                                                    messsageToSign: self.messsageToSign,
                                                    vault: self.vault,
                                                    encryptionKeyHex: self.encryptionKeyHex,
                                                    isInitiateDevice: self.isInitiateDevice,
                                                    publicKeyEdDSA: publicKey ?? vault.pubKeyEdDSA)
                try await schnorrKeysign.KeysignWithRetry()
                self.signatures = schnorrKeysign.getSignatures()
                if self.signatures.isEmpty {
                    throw HelperError.runtimeError("fail to sign transaction")
                }
            case .MLDSA:
                status = .KeysignMLDSA
                let dilithiumKeysign = DilithiumKeysign(
                    keysignCommittee: self.keysignCommittee,
                    mediatorURL: self.mediatorURL,
                    sessionID: self.sessionID,
                    messageToSign: self.messsageToSign,
                    vault: self.vault,
                    encryptionKeyHex: self.encryptionKeyHex,
                    chainPath: chainPath,
                    isInitiateDevice: self.isInitiateDevice,
                    publicKey: vault.publicKeyMLDSA44 ?? ""
                )
                try await dilithiumKeysign.DilithiumKeysignWithRetry()
                self.dilithiumSignatures = dilithiumKeysign.getSignatures()
                if self.dilithiumSignatures.isEmpty {
                    throw HelperError.runtimeError("fail to sign transaction")
                }
            }
            await broadcastTransaction()
            if let customMessagePayload {
                setTxid(customMessagePayload.message)
            }
            // broadcastTransaction owns its terminal status — don't overwrite a
            // failure (or retry request) set by handleBroadcastError.
            if status != .KeysignFailed && status != .KeysignRetryRequested {
                setStatus(.KeysignFinished)
            }
        } catch {
            logger.error("TSS keysign failed, error: \(error.localizedDescription, privacy: .public)")
            keysignError = error.localizedDescription
            setStatus(.KeysignFailed)
        }

    }

    func startKeysignGG20() async {
        defer {
            messagePuller?.stop()
        }
        for msg in messsageToSign {
            do {
                try await keysignOneMessageWithRetry(msg: msg, attempt: 1)
            } catch {
                logger.error("TSS keysign failed, error: \(error.localizedDescription, privacy: .public)")
                keysignError = error.localizedDescription
                setStatus(.KeysignFailed)
                return
            }
        }

        await broadcastTransaction()

        if let customMessagePayload {
            setTxid(customMessagePayload.message)
        }
        if status != .KeysignFailed && status != .KeysignRetryRequested {
            setStatus(.KeysignFinished)
        }
    }
    // Return value bool indicate whether keysign should be retried
    func keysignOneMessageWithRetry(msg: String, attempt: UInt8) async throws {
        logger.info("signing message:\(msg)")
        let msgHash = Utils.getMessageBodyHash(msg: msg)
        let keySignVerify = KeysignVerify(serverAddr: self.mediatorURL,
                                          sessionID: self.sessionID)
        var pubkey = ""
        switch self.keysignType {
        case .ECDSA:
            pubkey = vault.pubKeyECDSA
        case .EdDSA:
            pubkey = vault.pubKeyEdDSA
        case .MLDSA:
            pubkey = vault.publicKeyMLDSA44 ?? ""
        }
        let isEncryptGCM = await FeatureFlagService().isFeatureEnabled(feature: .EncryptGCM)
        self.tssMessenger = TssMessengerImpl(mediatorUrl: self.mediatorURL,
                                             sessionID: self.sessionID,
                                             messageID: msgHash,
                                             encryptionKeyHex: encryptionKeyHex,
                                             vaultPubKey: pubkey,
                                             isKeygen: false,
                                             encryptGCM: isEncryptGCM)
        self.stateAccess = LocalStateAccessorImpl(vault: self.vault)
        var err: NSError?
        // keysign doesn't need to recreate preparams
        self.tssService = TssNewService(self.tssMessenger, self.stateAccess, false, &err)
        if let err {
            throw err
        }
        guard let service = self.tssService else {
            throw HelperError.runtimeError("TSS service instance is nil")
        }

        self.messagePuller?.pollMessages(mediatorURL: self.mediatorURL,
                                         sessionID: self.sessionID,
                                         localPartyKey: self.vault.localPartyID,
                                         tssService: service,
                                         messageID: msgHash)

        let keysignReq = TssKeysignRequest()
        keysignReq.localPartyKey = self.vault.localPartyID
        keysignReq.keysignCommitteeKeys = self.keysignCommittee.joined(separator: ",")

        if let keysignPayload {
            keysignReq.derivePath = keysignPayload.coin.coinType.derivationPath()
        } else {
            // TODO: Should we use Ether as default derivationPath?
            keysignReq.derivePath = TokensStore.Token.ethereum.coinType.derivationPath()
        }

        // sign messages one by one , since the msg is in hex format , so we need convert it to base64
        // and then pass it to TSS for keysign
        if let msgToSign = Data(hexString: msg)?.base64EncodedString() {
            keysignReq.messageToSign = msgToSign
        }

        do {
            switch self.keysignType {
            case .ECDSA:
                keysignReq.pubKey = self.vault.pubKeyECDSA
                self.status = .KeysignECDSA
            case .EdDSA:
                keysignReq.pubKey = self.vault.pubKeyEdDSA
                self.status = .KeysignEdDSA
            case .MLDSA:
                throw HelperError.runtimeError("MLDSA keysign is not supported in GG20 mode")
            }
            if let service = self.tssService {
                let resp = try await tssKeysign(service: service, req: keysignReq, keysignType: keysignType)
                if resp.r.isEmpty || resp.s.isEmpty {
                    throw TssKeysignError.keysignFail
                }
                self.signatures[msg] = resp
                await keySignVerify.markLocalPartyKeysignComplete(message: msgHash, sig: resp)
            }

            self.messagePuller?.stop()
            try await Task.sleep(for: .seconds(1)) // backoff for 1 seconds , so other party can finish appropriately
        } catch {
            self.messagePuller?.stop()
            // Check whether the other party already have the signature
            logger.error("keysign failed, error:\(error.localizedDescription) , attempt:\(attempt)")
            let resp = await keySignVerify.checkKeySignComplete(message: msgHash)
            if resp != nil {
                self.signatures[msg] = resp
                return
            }

            if attempt < 3 {
                logger.info("retry keysign")
                try await keysignOneMessageWithRetry(msg: msg, attempt: attempt + 1)
            } else {
                throw error
            }
        }
    }

    func stopMessagePuller() {
        messagePuller?.stop()
    }

    func tssKeysign(service: TssServiceImpl, req: TssKeysignRequest, keysignType: KeyType) async throws -> TssKeysignResponse {
        let t = Task.detached(priority: .high) {
            switch keysignType {
            case .ECDSA:
                return try service.keysignECDSA(req)
            case .EdDSA:
                return try service.keysignEdDSA(req)
            case .MLDSA:
                throw HelperError.runtimeError("MLDSA keysign is not supported via TSS service")
            }
        }
        return try await t.value
    }

    func getSignedTransaction(keysignPayload: KeysignPayload) throws -> SignedTransactionType {
        var signedTransactions: [SignedTransactionResult] = []

        if let approvePayload = keysignPayload.approvePayload {
            let swaps = THORChainSwaps()
            let transaction = try swaps.getSignedApproveTransaction(approvePayload: approvePayload, keysignPayload: keysignPayload, signatures: signatures)
            signedTransactions.append(transaction)
        }

        if let swapPayload = keysignPayload.swapPayload {
            let incrementNonce = keysignPayload.approvePayload != nil
            switch swapPayload {
            case .thorchain(let payload), .thorchainChainnet(let payload), .thorchainStagenet(let payload):
                let swaps = THORChainSwaps()
                let transaction = try swaps.getSignedTransaction(swapPayload: payload, keysignPayload: keysignPayload, signatures: signatures, incrementNonce: incrementNonce)
                signedTransactions.append(transaction)

            case .generic(let payload):
                switch keysignPayload.coin.chain {
                case .solana:
                    let swaps = SolanaSwaps()
                    let transaction = try swaps.getSignedTransaction(swapPayload: payload, keysignPayload: keysignPayload, signatures: signatures)
                    signedTransactions.append(transaction)
                default:
                    let swaps = OneInchSwaps()
                    let transaction = try swaps.getSignedTransaction(payload: payload, keysignPayload: keysignPayload, signatures: signatures, incrementNonce: incrementNonce)
                    signedTransactions.append(transaction)
                }
            case .mayachain(let payload):
                if keysignPayload.coin.chainType != .EVM || keysignPayload.coin.isNativeToken {
                    break
                }
                let swaps = THORChainSwaps()
                let transaction = try swaps.getSignedTransaction(swapPayload: payload, keysignPayload: keysignPayload, signatures: signatures, incrementNonce: incrementNonce)
                signedTransactions.append(transaction)
            case .swapkit(let payload):
                // Phase 2 wires the payload up to here; the actual PSBT
                // sign + compile path lands in a follow-up. Throw a typed
                // error so a SwapKit BTC swap that reaches keysign without
                // the signing path in place fails visibly rather than
                // silently dropping signatures.
                throw SwapKitError.unsupportedTxType(payload.txType)
            }
        }

        if let signedTransactionType = SignedTransactionType(transactions: signedTransactions) {
            return signedTransactionType
        }

        switch keysignPayload.coin.chain.chainType {
        case .UTXO:
            let utxoHelper = UTXOChainsHelper(coin: keysignPayload.coin.coinType)
            let transaction = try utxoHelper.getSignedTransaction(keysignPayload: keysignPayload, signatures: signatures)
            return .regular(transaction)

        case .Cardano:
            let transaction = try CardanoHelper.getSignedTransaction(vaultHexPubKey: vault.pubKeyEdDSA, keysignPayload: keysignPayload, signatures: signatures)
            return .regular(transaction)
        case .EVM:
            if keysignPayload.coin.isNativeToken {
                let helper = EVMHelper.getHelper(coin: keysignPayload.coin)
                let transaction = try helper.getSignedTransaction(keysignPayload: keysignPayload, signatures: signatures)
                return .regular(transaction)
            } else {
                let helper = ERC20Helper.getHelper(coin: keysignPayload.coin)
                let transaction = try helper.getSignedTransaction(keysignPayload: keysignPayload, signatures: signatures)
                return .regular(transaction)
            }

        case .THORChain:
            switch keysignPayload.coin.chain {
            case .thorChain, .thorChainChainnet, .thorChainStagenet:
                let transaction = try THORChainHelper.getSignedTransaction(keysignPayload: keysignPayload, signatures: signatures)
                return .regular(transaction)
            case .mayaChain:
                let transaction = try MayaChainHelper.getSignedTransaction(keysignPayload: keysignPayload, signatures: signatures)
                return .regular(transaction)
            default:
                break
            }

        case .Solana:
            let transaction = try SolanaHelper.getSignedTransaction(keysignPayload: keysignPayload, signatures: signatures)
            return .regular(transaction)

        case .Sui:
            let transaction = try SuiHelper.getSignedTransaction(keysignPayload: keysignPayload, signatures: signatures)
            return .regular(transaction)

        case .Polkadot:
            if keysignPayload.coin.chain == .bittensor {
                let transaction = try BittensorHelper.getSignedTransaction(keysignPayload: keysignPayload, signatures: signatures)
                return .regular(transaction)
            }
            let transaction = try PolkadotHelper.getSignedTransaction(keysignPayload: keysignPayload, signatures: signatures)
            return .regular(transaction)

        case .Cosmos:
            let helper = try CosmosHelper.getHelper(forChain: keysignPayload.coin.chain)
            if keysignPayload.coin.chain == .qbtc {
                let transaction = try helper.getSignedTransaction(keysignPayload: keysignPayload, dilithiumSignatures: dilithiumSignatures)
                return .regular(transaction)
            }
            let transaction = try helper.getSignedTransaction(keysignPayload: keysignPayload, signatures: signatures)
            return .regular(transaction)

        case .Ton:
            let transaction = try TonHelper.getSignedTransaction(keysignPayload: keysignPayload, signatures: signatures)
            return .regular(transaction)
        case .Ripple:
            let transaction = try RippleHelper.getSignedTransaction(keysignPayload: keysignPayload, signatures: signatures)
            return .regular(transaction)
        case .Tron:
            let transaction = try TronHelper.getSignedTransaction(
                keysignPayload: keysignPayload,
                signatures: signatures            )
            return .regular(transaction)
        }

        throw HelperError.runtimeError("Unexpected error")
    }

    func broadcastTransaction() async {
        guard let keysignPayload else { return }

        guard !keysignPayload.skipBroadcast else {
            print("Transaction not broadcasted, skipBroadcast is set to true")
            self.txid = ""
            return
        }

        let transactionType: SignedTransactionType

        do {
            transactionType = try getSignedTransaction(keysignPayload: keysignPayload)
        } catch {
            return handleHelperError(err: error)
        }

        do {
            switch transactionType {
            case .regular(let tx):
                switch keysignPayload.coin.chain {
                case .thorChain, .thorChainChainnet, .thorChainStagenet:
                    let service = ThorchainServiceFactory.getService(for: keysignPayload.coin.chain)
                    let broadcastResult = await service.broadcastTransaction(jsonString: tx.rawTransaction)
                    switch broadcastResult {
                    case .success(let txHash):
                        self.txid = txHash

                        // Store pending transaction for nonce tracking
                        if case .THORChain(_, let sequence, _, _, _) = keysignPayload.chainSpecific {

                            PendingTransactionManager.shared.addPendingTransaction(
                                txHash: txHash,
                                address: keysignPayload.coin.address,
                                chain: keysignPayload.coin.chain,
                                sequence: sequence
                            )

                        }
                    case .failure(let error):
                        throw error
                    }
                case .mayaChain:
                    let broadcastResult = await MayachainService.shared.broadcastTransaction(jsonString: tx.rawTransaction)
                    switch broadcastResult {
                    case .success(let txHash):
                        self.txid = txHash

                        // Store pending transaction for nonce tracking
                        if case .MayaChain(_, let sequence, _) = keysignPayload.chainSpecific {
                            PendingTransactionManager.shared.addPendingTransaction(
                                txHash: txHash,
                                address: keysignPayload.coin.address,
                                chain: keysignPayload.coin.chain,
                                sequence: sequence
                            )
                        }
                    case .failure(let error):
                        throw error
                    }
                case .ethereum, .avalanche, .arbitrum, .bscChain, .base, .optimism, .polygon, .polygonV2, .blast, .cronosChain, .zksync, .ethereumSepolia, .mantle, .hyperliquid, .sei:
                    let service = try EvmService.getService(forChain: keysignPayload.coin.chain)
                    self.txid = try await service.broadcastTransaction(hex: tx.rawTransaction)
                case .bitcoin:
                    do {
                        let transactionHash = try await UTXOTransactionsService.broadcastBitcoinTransaction(signedTransaction: tx.rawTransaction)
                        self.txid = transactionHash
                        // Fire-and-forget: don't block the broadcast confirmation on cache eviction.
                        Task { await BlockchairService.shared.clearUTXOCache(for: keysignPayload.coin) }
                    } catch {
                        await self.handleBroadcastError(error: error, transactionType: transactionType)
                    }
                case .bitcoinCash, .litecoin, .dogecoin, .dash, .zcash:
                    let chainName = keysignPayload.coin.chain.name.lowercased()
                    do {
                        let transactionHash = try await UTXOTransactionsService.broadcastTransaction(chain: chainName, signedTransaction: tx.rawTransaction)
                        self.txid = transactionHash
                        Task { await BlockchairService.shared.clearUTXOCache(for: keysignPayload.coin) }
                    } catch {
                        await self.handleBroadcastError(error: error, transactionType: transactionType)
                    }
                case .cardano:
                    do {
                        self.txid = try await CardanoService.shared.broadcastTransaction(
                            signedTransaction: tx.rawTransaction,
                            precomputedTxId: tx.transactionHash
                        )
                    } catch {
                        await self.handleBroadcastError(error: error, transactionType: transactionType)
                    }
                case .gaiaChain, .kujira, .osmosis, .dydx, .terra, .terraClassic, .noble, .akash, .qbtc:
                    let service = try CosmosService.getService(forChain: keysignPayload.coin.chain)
                    let broadcastResult = await service.broadcastTransaction(jsonString: tx.rawTransaction)
                    switch broadcastResult {
                    case .success(let hash):
                        self.txid = hash

                        // Store pending transaction for nonce tracking
                        if case .Cosmos(_, let sequence, _, _, _) = keysignPayload.chainSpecific {
                            PendingTransactionManager.shared.addPendingTransaction(
                                txHash: hash,
                                address: keysignPayload.coin.address,
                                chain: keysignPayload.coin.chain,
                                sequence: sequence
                            )
                        }
                    case .failure(let err):
                        throw err
                    }
                case .solana:
                    self.txid = try await SolanaService.shared.sendSolanaTransaction(encodedTransaction: tx.rawTransaction) ?? .empty
                case .sui:
                    self.txid = try await SuiService.shared.executeTransactionBlock(unsignedTransaction: tx.rawTransaction, signature: tx.signature ?? .empty)
                case .polkadot:
                    // Fast broadcast - extrinsic index will be discovered lazily during status checks
                    self.txid = try await PolkadotService.shared.broadcastTransaction(hex: tx.rawTransaction)

                case .bittensor:
                    self.txid = try await BittensorService.shared.broadcastTransaction(hex: tx.rawTransaction)

                case .ton:
                    let base64Hash = try await TonService.shared.broadcastTransaction(tx.rawTransaction)
                    if base64Hash.isEmpty {
                        self.txid = tx.transactionHash
                    } else {
                        self.txid = Data(base64Encoded: base64Hash)?.hexString ?? tx.transactionHash
                    }
                case .ripple:
                    self.txid = try await RippleService.shared.broadcastTransaction(tx.rawTransaction)

                case .tron:

                    let broadcastResult = await TronService.shared.broadcastTransaction(jsonString: tx.rawTransaction)

                    switch broadcastResult {
                    case .success(let txHash):
                        self.txid = txHash
                    case .failure(let error):
                        throw error
                    }
                }

            case .regularWithApprove(let approve, let transaction):
                let service = try EvmService.getService(forChain: keysignPayload.coin.chain)
                let approveTxHash = try await service.broadcastTransaction(hex: approve.rawTransaction)
                let regularTxHash = try await service.broadcastTransaction(hex: transaction.rawTransaction)
                self.approveTxid = approveTxHash
                self.txid = regularTxHash
            }
        } catch {
            await handleBroadcastError(error: error, transactionType: transactionType)
        }

        if txid == "Transaction already broadcasted." {
            txid = transactionType.transactionHash
            approveTxid = transactionType.approveTransactionHash
        }

        // Save to pending transactions for status tracking
        savePendingTransaction()
    }

    private func savePendingTransaction() {
        guard let keysignPayload = keysignPayload,
              !txid.isEmpty,
              txid != "Transaction already broadcasted." else {
            return
        }

        let storage = StoredPendingTransactionStorage.shared
        let config = ChainStatusConfig.config(for: keysignPayload.coin.chain)

        Task {
            try? storage.save(
                txHash: txid,
                chain: keysignPayload.coin.chain,
                status: .broadcasted(estimatedTime: config.estimatedTime),
                coinTicker: keysignPayload.coin.ticker,
                amount: keysignPayload.toAmount.description,
                toAddress: keysignPayload.toAddress
            )
        }
    }

    func customMessageSignature() -> String {
        // currently keysign for custom message is using ETH , and the signature should be get signature with recoveryid
        switch signatures.first?.value.getSignatureWithRecoveryID() {
        case .success(let sig):
            return sig.hexString
        case .none, .failure:
            return .empty
        }
    }

    func handleBroadcastError(error: Error, transactionType: SignedTransactionType) async {
        if let retryable = error as? RetryableBroadcastError,
           broadcastRetryCount < Self.maxBroadcastRetries {
            broadcastRetryCount += 1
            logger.warning("broadcast failed with retryable error (\(retryable.retryReason.userFacingMessage, privacy: .public)); requesting retry")
            self.retryReason = retryable.retryReason
            setStatus(.KeysignRetryRequested)
            return
        }

        var errMessage: String = ""
        switch error {
        case HelperError.runtimeError(let errDetail):
            errMessage = "Failed to broadcast transaction,\(errDetail)"
        case RpcEvmServiceError.rpcError(let code, let message):
            logger.error("rpc error code:\(code), message:\(message, privacy: .public)")
            if message == "already known"
                || message == "replacement transaction underpriced"
                || message.contains("This transaction has already been processed") {
                logger.info("the transaction already broadcast, code:\(code)")
                setTxid(transactionType.transactionHash)
                self.approveTxid = transactionType.approveTransactionHash
                return
            }
        default:

            // Check for Cardano "already broadcasted" errors
            if error.localizedDescription.contains("BadInputsUTxO") {
                logger.info("Cardano transaction already broadcast - using hash from transactionType \(transactionType.transactionHash, privacy: .public)")
                setTxid(transactionType.transactionHash)
                self.approveTxid = transactionType.approveTransactionHash
                return
            }

            errMessage = "Failed to broadcast transaction,error:\(error.localizedDescription)"
        }

        // Chain-agnostic fallback: when a co-signing peer wins the broadcast
        // race, our broadcast call fails (mempool / sequence / duplicate
        // errors) but the signed tx is already on-chain. Look it up by hash
        // before declaring failure — every chain has the same deterministic
        // hash so this works without per-chain string matching.
        if await isAlreadyOnChain(transactionType: transactionType) {
            logger.info("transaction already on-chain via peer broadcast — using hash \(transactionType.transactionHash, privacy: .public)")
            setTxid(transactionType.transactionHash)
            self.approveTxid = transactionType.approveTransactionHash
            if let coin = keysignPayload?.coin, coin.chainType == .UTXO {
                await BlockchairService.shared.clearUTXOCache(for: coin)
            }
            return
        }

        logger.error("\(errMessage, privacy: .public)")
        self.keysignError = errMessage
        setStatus(.KeysignFailed)
    }

    /// Best-effort check that the signed tx is already accepted on the chain
    /// (mempool or block). Returns true only on positive evidence (`.confirmed`
    /// or `.pending`); `.failed` is conclusive and fails fast. `.notFound` and
    /// transient lookup errors are retried with backoff because a peer-broadcast
    /// tx often takes a few seconds to propagate to our RPC node / indexer
    /// (Cosmos LCD index lag is the worst offender), and a single early miss
    /// would otherwise show the user a "failed" screen for a tx that's already
    /// landing.
    private func isAlreadyOnChain(transactionType: SignedTransactionType) async -> Bool {
        guard let chain = keysignPayload?.coin.chain else { return false }
        let hash = transactionType.transactionHash
        guard !hash.isEmpty else { return false }

        let maxAttempts = 3
        let backoff: Duration = .seconds(2)

        for attempt in 1...maxAttempts {
            do {
                let result = try await TransactionStatusService.shared.checkTransactionStatus(txHash: hash, chain: chain)
                switch result.status {
                case .confirmed, .pending:
                    return true
                case .failed:
                    return false
                case .notFound:
                    break
                }
            } catch {
                logger.warning("hash-verify lookup failed (attempt \(attempt)/\(maxAttempts)) for \(hash, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }

            if attempt < maxAttempts {
                try? await Task.sleep(for: backoff)
            }
        }

        return false
    }

    func handleHelperError(err: Error) {
        var errMessage: String
        switch err {
        case HelperError.runtimeError(let errDetail):
            errMessage = "Failed to get signed transaction,error:\(errDetail)"

        default:
            errMessage = "Failed to get signed transaction,error:\(err.localizedDescription)"
        }
        // Class is @MainActor — assign directly. A previous `DispatchQueue.main.async`
        // wrapper raced with `tssKeysign`'s post-broadcast `status = .KeysignFinished`
        // guard: the dispatched block ran on the next runloop tick, after the guard
        // had already overwritten the status. See vultisig-ios#4327.
        self.keysignError = errMessage
        setStatus(.KeysignFailed)
    }

    func getCalculatedNetworkFee() -> (feeCrypto: String, feeFiat: String) {
        guard let keysignPayload else { return (.empty, .empty) }
        return gasViewModel.getCalculatedNetworkFee(payload: keysignPayload)
    }
}
