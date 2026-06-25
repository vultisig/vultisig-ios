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
    /// Neutral terminal state: the broadcast was interrupted (the in-flight
    /// HTTP call was cancelled) and we could NOT positively confirm the tx
    /// on-chain. The tx may already have landed, so we surface the
    /// deterministic hash + explorer link instead of a hard failure and
    /// avoid pushing the user toward a one-tap re-broadcast (double-spend
    /// risk). Distinct from `.KeysignFailed`, which is a confirmed failure.
    case KeysignBroadcastUnconfirmed
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

    /// Injectable seam for the on-chain hash lookup so tests can supply a fake
    /// that returns `.confirmed` / `.notFound` / throws. Defaults to the
    /// production singleton so runtime behaviour is unchanged.
    var transactionStatusChecker: TransactionStatusChecking = TransactionStatusService.shared

    /// Per-message stage budget. Each message's inbound poll already caps at
    /// 60s per attempt (see the DKLS/Schnorr/Dilithium `pullInboundMessages`
    /// loops); this adds headroom for the setup-message round-trips so a single
    /// healthy-but-slow message doesn't trip the safety net.
    private static let perMessageStageBudget: Duration = .seconds(90)

    /// Fixed headroom on top of the per-message budget for the post-signing
    /// broadcast (RPC submit + the on-chain verification backoff).
    private static let broadcastStageHeadroom: Duration = .seconds(30)

    /// Top-level timeout for a single keysign run (TSS exchange + broadcast).
    /// Underlying poll loops can stall without producing a terminal status —
    /// iOS suspending the network session in background, DKLS retry exhaustion,
    /// a peer that never sent its share — so this is the safety net that flips
    /// the UI into the retry-requested view. See vultisig-ios#4327.
    ///
    /// Messages are signed sequentially, so the budget scales with the message
    /// count. A flat timeout fired on healthy multi-message ceremonies (e.g. a
    /// UTXO send with several inputs), manufacturing the very retry-vs-orphan
    /// race this guards against rather than catching a real hang.
    var keysignStageTimeout: Duration {
        let messageCount = max(messsageToSign.count, 1)
        return Self.perMessageStageBudget * messageCount + Self.broadcastStageHeadroom
    }

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

    /// Drives the keysign Rive animation's `progessPercentage` bar (0–100). The
    /// bar fills as signing advances through its phases, mirroring the Android
    /// client. Without an explicit value the bar stays empty regardless of the
    /// flow (custom message and swap signing reported this), since nothing else
    /// binds the property.
    var signingProgress: Float {
        switch status {
        case .CreatingInstance:
            return 0
        case .KeysignECDSA:
            return 33
        case .KeysignEdDSA, .KeysignMLDSA:
            return 66
        case .KeysignFinished:
            return 100
        case .KeysignFailed, .KeysignRetryRequested, .KeysignVaultMismatch, .KeysignBroadcastUnconfirmed:
            return 0
        }
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
        // Snapshot the (message-count-scaled) budget before entering the group
        // so the non-isolated sleeper closure stays Sendable-clean.
        let stageTimeout = keysignStageTimeout
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
                    try await Task.sleep(for: stageTimeout)
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
            guard !Self.isTerminalStatus(status) else { return }
            logger.warning("keysign exceeded \(stageTimeout, privacy: .public) stage timeout — requesting retry")
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

    /// A terminal status that `broadcastTransaction`/`handleBroadcastError`
    /// (or the stage-timeout race) may have already set. Callers must NOT
    /// overwrite it with `.KeysignFinished` afterwards. `.KeysignBroadcastUnconfirmed`
    /// is included so a cancelled-but-unconfirmed broadcast isn't masked as a
    /// false success by the post-broadcast finish guard.
    static func isTerminalStatus(_ status: KeysignStatus) -> Bool {
        switch status {
        case .KeysignFinished, .KeysignFailed, .KeysignVaultMismatch,
             .KeysignRetryRequested, .KeysignBroadcastUnconfirmed:
            return true
        case .CreatingInstance, .KeysignECDSA, .KeysignEdDSA, .KeysignMLDSA:
            return false
        }
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
            // The body may have been cancelled mid-flight (stage timeout)
            // without a poll loop observing it. Gate broadcast on the same
            // terminal-status check the finish guard uses so an orphaned
            // ceremony — whose status the timeout already flipped to
            // .KeysignRetryRequested — can never broadcast.
            guard !Self.isTerminalStatus(status), !Task.isCancelled else { return }
            await broadcastTransaction()
            if let customMessagePayload {
                setTxid(customMessagePayload.message)
            }
            // broadcastTransaction owns its terminal status — don't overwrite a
            // failure, retry request, or the neutral "couldn't confirm" state
            // set by handleBroadcastError.
            if !Self.isTerminalStatus(status) {
                setStatus(.KeysignFinished)
            }
        } catch is CancellationError {
            // Stage-timeout cancellation: the timeout handler owns the terminal
            // status (.KeysignRetryRequested). Do not overwrite it with a
            // failure and do not broadcast.
            logger.warning("DKLS keysign cancelled — leaving terminal status to the timeout handler")
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
            // Cooperative cancellation: the stage-level timeout cancels this
            // task group on a stall; bail before signing the next message so an
            // abandoned ceremony can't proceed to broadcast.
            if Task.isCancelled { return }
            do {
                try await keysignOneMessageWithRetry(msg: msg, attempt: 1)
            } catch is CancellationError {
                return
            } catch {
                logger.error("TSS keysign failed, error: \(error.localizedDescription, privacy: .public)")
                keysignError = error.localizedDescription
                setStatus(.KeysignFailed)
                return
            }
        }

        // The body may have been cancelled mid-flight (stage timeout) without a
        // poll loop observing it. Gate broadcast on the same terminal-status
        // check the finish guard uses so an orphaned ceremony — whose status the
        // timeout already flipped to .KeysignRetryRequested — can never broadcast.
        guard !Self.isTerminalStatus(status), !Task.isCancelled else { return }
        await broadcastTransaction()

        if let customMessagePayload {
            setTxid(customMessagePayload.message)
        }
        if !Self.isTerminalStatus(status) {
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
            // A cancellation is not a signing failure — propagate so the
            // abandoned ceremony unwinds instead of retrying.
            if error is CancellationError { throw error }
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

        // Non-swap approve bundle (e.g. a native-coin deposit): an approve with NO swap
        // payload on a native EVM coin. The approve was appended above at nonce
        // N; append the main `memo`-call tx at nonce N+1 so the result is
        // [approve@N, call@N+1] → `.regularWithApprove`. Mirrors the hash branch
        // in `KeysignMessageFactory`; without it the gate below would build a
        // lone-approve `.regular` and the main call would never broadcast.
        if keysignPayload.approvePayload != nil,
           keysignPayload.swapPayload == nil,
           keysignPayload.coin.chain.chainType == .EVM,
           keysignPayload.coin.isNativeToken {
            let helper = EVMHelper.getHelper(coin: keysignPayload.coin)
            let transaction = try helper.getSignedTransaction(keysignPayload: keysignPayload, signatures: signatures, incrementNonce: true)
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
                    let transaction = try SolanaHelper.getSignedTransaction(swapPayload: payload, keysignPayload: keysignPayload, signatures: signatures)
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
                // Dispatch on SwapKit's `meta.txType`. PSBT (BTC), SUI, and
                // TRON have SwapKit-specific signers because their pre-built
                // bytes drive transaction assembly directly. TON + CARDANO
                // fall through to the per-chain helpers at the bottom of
                // this method — the SwapKit builder already pointed
                // `toAddress` / `toAmount` at the deposit address + amount.
                switch payload.txType {
                case "PSBT":
                    let tx = try SwapKitBTCSigner.compileSignedTransaction(
                        payload: payload,
                        signatures: signatures,
                        pubKeyHex: keysignPayload.coin.hexPublicKey
                    )
                    signedTransactions.append(tx)
                case "PSBT_DOGE":
                    let tx = try SwapKitDogeSigner.compileSignedTransaction(
                        payload: payload,
                        signatures: signatures,
                        pubKeyHex: keysignPayload.coin.hexPublicKey
                    )
                    signedTransactions.append(tx)
                case "PSBT_BCH":
                    let tx = try SwapKitBCHSigner.compileSignedTransaction(
                        payload: payload,
                        signatures: signatures,
                        pubKeyHex: keysignPayload.coin.hexPublicKey
                    )
                    signedTransactions.append(tx)
                case "PSBT_DASH":
                    let tx = try SwapKitDashSigner.compileSignedTransaction(
                        payload: payload,
                        signatures: signatures,
                        pubKeyHex: keysignPayload.coin.hexPublicKey
                    )
                    signedTransactions.append(tx)
                case "PSBT_ZEC":
                    let tx = try SwapKitZcashSigner.compileSignedTransaction(
                        payload: payload,
                        signatures: signatures,
                        pubKeyHex: keysignPayload.coin.hexPublicKey,
                        zcashBranchId: keysignPayload.chainSpecific.zcashBranchId
                    )
                    signedTransactions.append(tx)
                case "SUI":
                    let tx = try SwapKitSuiSigner.compileSignedTransaction(
                        payload: payload,
                        signatures: signatures,
                        pubKeyHex: keysignPayload.coin.hexPublicKey
                    )
                    signedTransactions.append(tx)
                case "TRON":
                    let tx = try SwapKitTronSigner.compileSignedTransaction(
                        payload: payload,
                        signatures: signatures,
                        pubKeyHex: keysignPayload.coin.hexPublicKey
                    )
                    signedTransactions.append(tx)
                case "CARDANO_PREBUILT":
                    // Cardano signs with Ed25519 against the vault's EdDSA
                    // public key — pass `vault.pubKeyEdDSA` (same convention
                    // as the deposit-only send path in `CardanoHelper`).
                    let tx = try SwapKitCardanoSigner.compileSignedTransaction(
                        payload: payload,
                        signatures: signatures,
                        pubKeyHex: vault.pubKeyEdDSA
                    )
                    signedTransactions.append(tx)
                case "TON", "CARDANO", "XRP":
                    // Deposit-only flows fall through to the per-chain helper
                    // at the bottom of this method — the SwapKit builder
                    // already pointed `toAddress` / `toAmount` (and memo
                    // for XRP destination tag) at the deposit.
                    break
                case "EVM", "SOLANA":
                    throw SwapKitError.unsupportedTxType(payload.txType)
                default:
                    throw SwapKitError.unsupportedTxType(payload.txType)
                }
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
            logger.info("Transaction not broadcasted, skipBroadcast is set to true")
            self.txid = ""
            return
        }

        let transactionType: SignedTransactionType

        do {
            transactionType = try getSignedTransaction(keysignPayload: keysignPayload)
        } catch {
            return handleHelperError(err: error)
        }

        // Idempotency guard: if a prior attempt for this exact deterministic
        // hash was already recorded (e.g. a previous broadcast that got
        // cancelled mid-flight), short-circuit to success when the tx is on
        // chain instead of broadcasting again. The deterministic hash is the
        // same across attempts, so this protects every (re-)broadcast path from
        // a double-spend. Gated on an existing record so first broadcasts pay no
        // extra round-trip.
        if hasPriorBroadcastAttempt(for: transactionType.transactionHash),
           await isAlreadyOnChain(transactionType: transactionType) {
            logger.info("idempotency guard: prior attempt for \(transactionType.transactionHash, privacy: .public) already on-chain — skipping re-broadcast")
            await applyBroadcastSuccess(transactionType: transactionType)
            savePendingTransaction()
            return
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
                        let transactionHash = try await UTXOTransactionsService.broadcastBitcoinTransaction(signedTransaction: tx.rawTransaction, expectedTxid: tx.transactionHash)
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

    /// Whether a prior broadcast attempt for this deterministic hash was
    /// already recorded. Used to gate the idempotency pre-broadcast check so it
    /// only runs on retry paths, not on every first broadcast.
    private func hasPriorBroadcastAttempt(for txHash: String) -> Bool {
        guard !txHash.isEmpty else { return false }
        do {
            return try StoredPendingTransactionStorage.shared.get(txHash: txHash) != nil
        } catch {
            logger.warning("idempotency lookup failed for \(txHash, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
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
        switch keysignType {
        case .ECDSA:
            guard let sig = signatures.first?.value else { return .empty }
            switch sig.getSignatureWithRecoveryID() {
            case .success(let data): return data.hexString
            case .failure: return .empty
            }
        case .EdDSA:
            guard let sig = signatures.first?.value else { return .empty }
            switch sig.getSignature() {
            case .success(let data): return data.hexString
            case .failure: return .empty
            }
        case .MLDSA:
            return dilithiumSignatures.first?.value.signature ?? .empty
        }
    }

    func handleBroadcastError(error: Error, transactionType: SignedTransactionType) async {
        // (A) A cancellation is NOT conclusive evidence the broadcast failed.
        // SwiftUI tears down the `.task`-backed Task on view teardown / scene
        // change, which cancels the in-flight broadcast HTTP call — the tx may
        // already have reached the mempool/proxy. Classify it as non-conclusive
        // and route into detached verification instead of declaring failure.
        // It is deliberately NOT treated as a `RetryableBroadcastError`: an
        // auto-re-broadcast of a tx that may have landed risks a double-spend.
        if Self.isCancellation(error) {
            logger.warning("broadcast interrupted by cancellation — verifying on-chain before declaring failure")
            await handleCancelledBroadcast(transactionType: transactionType)
            return
        }

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
            await applyBroadcastSuccess(transactionType: transactionType)
            return
        }

        logger.error("\(errMessage, privacy: .public)")
        self.keysignError = errMessage
        setStatus(.KeysignFailed)
    }

    /// True for a Swift Concurrency cancellation or a URL-layer cancellation,
    /// including the `URLError.cancelled` that `HTTPClient` re-throws as a fresh
    /// `CancellationError` and any cancellation wrapped in `HTTPError`.
    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if (error as? URLError)?.code == .cancelled { return true }
        if case let HTTPError.networkError(underlying) = error {
            return isCancellation(underlying)
        }
        return false
    }

    /// (B) + (C) Handles a broadcast that was interrupted by cancellation.
    /// The hash lookup runs detached so it does NOT inherit the cancelled
    /// parent context (otherwise `HTTPClient`'s `Task.checkCancellation()`
    /// short-circuits every RPC before any network I/O). If verification
    /// positively confirms the tx, treat it as a success exactly like a normal
    /// broadcast. Otherwise fall back to a neutral "couldn't confirm" state —
    /// never a hard failure with a raw `CancellationError` string.
    private func handleCancelledBroadcast(transactionType: SignedTransactionType) async {
        if await isAlreadyOnChain(transactionType: transactionType) {
            logger.info("cancelled broadcast confirmed on-chain — using hash \(transactionType.transactionHash, privacy: .public)")
            await applyBroadcastSuccess(transactionType: transactionType)
            return
        }

        logger.warning("cancelled broadcast could not be confirmed on-chain — neutral unconfirmed state for hash \(transactionType.transactionHash, privacy: .public)")
        setTxid(transactionType.transactionHash)
        self.approveTxid = transactionType.approveTransactionHash
        self.keysignError = "broadcastCouldNotConfirm".localized
        setStatus(.KeysignBroadcastUnconfirmed)
    }

    /// Mirrors the normal successful-broadcast bookkeeping: sets the txid +
    /// approve txid and clears the UTXO cache. Status is left to the caller's
    /// existing `KeysignFinished` guard (set txid → done).
    private func applyBroadcastSuccess(transactionType: SignedTransactionType) async {
        setTxid(transactionType.transactionHash)
        self.approveTxid = transactionType.approveTransactionHash
        if let coin = keysignPayload?.coin, coin.chainType == .UTXO {
            await BlockchairService.shared.clearUTXOCache(for: coin)
        }
    }

    /// Best-effort check that the signed tx is already accepted on the chain
    /// (mempool or block). Returns true only on positive evidence (`.confirmed`
    /// or `.pending`); `.failed` is conclusive and fails fast. `.notFound` and
    /// transient lookup errors are retried with backoff because a peer-broadcast
    /// tx often takes a few seconds to propagate to our RPC node / indexer
    /// (Cosmos LCD index lag is the worst offender), and a single early miss
    /// would otherwise show the user a "failed" screen for a tx that's already
    /// landing.
    ///
    /// The lookup runs in a detached task so it does not inherit a cancelled
    /// parent context: `HTTPClient.request` checks `Task.checkCancellation()`
    /// as its first statement, so under a cancelled parent every RPC — and the
    /// backoff `Task.sleep` — would throw immediately, defeating the safety
    /// net. Value-type inputs (chain + hash) are captured before detaching to
    /// keep the closure Sendable-clean.
    private func isAlreadyOnChain(transactionType: SignedTransactionType) async -> Bool {
        guard let chain = keysignPayload?.coin.chain else { return false }
        let hash = transactionType.transactionHash
        guard !hash.isEmpty else { return false }

        let checker = transactionStatusChecker
        let log = logger

        return await Task.detached {
            let maxAttempts = 3
            let backoff: Duration = .seconds(2)

            for attempt in 1...maxAttempts {
                do {
                    let result = try await checker.checkTransactionStatus(txHash: hash, chain: chain)
                    switch result.status {
                    case .confirmed, .pending:
                        return true
                    case .failed:
                        return false
                    case .notFound:
                        break
                    }
                } catch {
                    log.warning("hash-verify lookup failed (attempt \(attempt)/\(maxAttempts)) for \(hash, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }

                if attempt < maxAttempts {
                    do {
                        try await Task.sleep(for: backoff)
                    } catch {
                        log.warning("hash-verify backoff interrupted: \(error.localizedDescription, privacy: .public)")
                        return false
                    }
                }
            }

            return false
        }.value
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
