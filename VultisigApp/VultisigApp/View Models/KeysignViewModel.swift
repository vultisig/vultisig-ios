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
    case KeysignFinished
    case KeysignFailed
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
    @Published var txid: String = .empty
    @Published var approveTxid: String?
    @Published var decodedMemo: String?

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
        let isEncryptGCM =  await FeatureFlagService().isFeatureEnabled(feature: .EncryptGCM)
        self.messagePuller = MessagePuller(encryptionKeyHex: encryptionKeyHex, pubKey: vault.pubKeyECDSA, encryptGCM: isEncryptGCM)
        self.isInitiateDevice = isInitiateDevice

        // Load extension memo decoding
        await loadFunctionName()
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
            print("EVM memo decoding error: \(error.localizedDescription)")
        }
    }

    func getTransactionExplorerURL(txid: String) -> String {
        guard let keysignPayload else { return .empty }
        return Endpoint.getExplorerURL(chain: keysignPayload.coin.chain, txid: txid)
    }

    func getSwapProgressURL(txid: String) -> String? {
        switch keysignPayload?.swapPayload {
        case .thorchain:
            return Endpoint.getSwapProgressURL(txid: txid)
        case .thorchainStagenet:
            return Endpoint.getStagenetSwapProgressURL(txid: txid)
        case .mayachain:
            return Endpoint.getMayaSwapTracker(txid: txid)
        case .generic(let payload):
            if payload.provider == .lifi {
                return Endpoint.getLifiSwapTracker(txid: txid)
            } else {
                return Endpoint.getExplorerURL(chain: payload.fromCoin.chain, txid: txid)
            }
        case .none:
            return nil
        }
    }

    func startKeysign() async {
        switch vault.libType {
        case .GG20, .none:
            await startKeysignGG20()
        case .DKLS:
            await startKeysignDKLS(isImport: false)
        case .KeyImport:
            await startKeysignDKLS(isImport: true)
        }
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
            }
            await broadcastTransaction()
            if let customMessagePayload {
                txid = customMessagePayload.message
            }
            status = .KeysignFinished
        } catch {
            logger.error("TSS keysign failed, error: \(error.localizedDescription)")
            keysignError = error.localizedDescription
            status = .KeysignFailed
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
                logger.error("TSS keysign failed, error: \(error.localizedDescription)")
                keysignError = error.localizedDescription
                status = .KeysignFailed
                return
            }
        }

        await broadcastTransaction()

        if let customMessagePayload {
            txid = customMessagePayload.message
        }
        status = .KeysignFinished
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
            case .thorchain(let payload), .thorchainStagenet(let payload):
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
            let transaction = try CardanoHelper.getSignedTransaction(vaultHexPubKey: vault.pubKeyEdDSA, vaultHexChainCode: vault.hexChainCode, keysignPayload: keysignPayload, signatures: signatures)
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
            case .thorChain, .thorChainStagenet:
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
            let transaction = try PolkadotHelper.getSignedTransaction(keysignPayload: keysignPayload, signatures: signatures)
            return .regular(transaction)

        case .Cosmos:
            let helper = try CosmosHelper.getHelper(forChain: keysignPayload.coin.chain)
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
                case .thorChain, .thorChainStagenet:
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
                    UTXOTransactionsService.broadcastBitcoinTransaction(signedTransaction: tx.rawTransaction) { result in
                        switch result {
                        case .success(let transactionHash):
                            self.txid = transactionHash
                            // Clear UTXO cache after successful broadcast to prevent using spent UTXOs
                            Task {
                                await BlockchairService.shared.clearUTXOCache(for: keysignPayload.coin)
                            }
                        case .failure(let error):
                            self.handleBroadcastError(error: error, transactionType: transactionType)
                        }
                    }
                case .bitcoinCash, .litecoin, .dogecoin, .dash, .zcash:
                    let chainName = keysignPayload.coin.chain.name.lowercased()
                    UTXOTransactionsService.broadcastTransaction(chain: chainName, signedTransaction: tx.rawTransaction) { result in
                        switch result {
                        case .success(let transactionHash):
                            self.txid = transactionHash
                            // Clear UTXO cache after successful broadcast to prevent using spent UTXOs
                            Task {
                                await BlockchairService.shared.clearUTXOCache(for: keysignPayload.coin)
                            }
                        case .failure(let error):
                            self.handleBroadcastError(error: error, transactionType: transactionType)
                        }
                    }
                case .cardano:
                    do {
                        self.txid = try await CardanoService.shared.broadcastTransaction(signedTransaction: tx.rawTransaction)
                    } catch {
                        self.handleBroadcastError(error: error, transactionType: transactionType)
                    }
                case .gaiaChain, .kujira, .osmosis, .dydx, .terra, .terraClassic, .noble, .akash:
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
            handleBroadcastError(error: error, transactionType: transactionType)
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
        guard let sig = signatures.first?.value else { return .empty }

        // Determine key type from chain — EdDSA for Solana/Polkadot/etc, ECDSA for EVM
        let isEdDSA: Bool
        if let chainName = customMessagePayload?.chain,
           let chain = Chain(name: chainName) {
            isEdDSA = chain.signingKeyType == .EdDSA
        } else {
            isEdDSA = false
        }

        if isEdDSA {
            switch sig.getSignature() {
            case .success(let data):
                return data.hexString
            case .failure:
                return .empty
            }
        } else {
            switch sig.getSignatureWithRecoveryID() {
            case .success(let data):
                return data.hexString
            case .failure:
                return .empty
            }
        }
    }

    func handleBroadcastError(error: Error, transactionType: SignedTransactionType) {
        var errMessage: String = ""
        switch error {
        case HelperError.runtimeError(let errDetail):
            errMessage = "Failed to broadcast transaction,\(errDetail)"
        case RpcEvmServiceError.rpcError(let code, let message):
            print("code:\(code), message:\(message)")
            if message == "already known"
                || message == "replacement transaction underpriced"
                || message.contains("This transaction has already been processed") {
                print("the transaction already broadcast,code:\(code)")
                self.txid = transactionType.transactionHash
                return
            }
        default:

            // Check for Cardano "already broadcasted" errors
            if error.localizedDescription.contains("BadInputsUTxO") || error.localizedDescription.contains("timed out") {
                print("Cardano transaction already broadcast - using correct hash from transactionType \(transactionType.transactionHash)")
                self.txid = transactionType.transactionHash
                return
            }

            errMessage = "Failed to broadcast transaction,error:\(error.localizedDescription)"
        }
        print(errMessage)
        DispatchQueue.main.async {
            self.keysignError = errMessage
            self.status = .KeysignFailed
        }
    }

    func handleHelperError(err: Error) {
        var errMessage: String
        switch err {
        case HelperError.runtimeError(let errDetail):
            errMessage = "Failed to get signed transaction,error:\(errDetail)"

        default:
            errMessage = "Failed to get signed transaction,error:\(err.localizedDescription)"
        }
        // since it failed to get transaction or failed to broadcast , go to failed page
        DispatchQueue.main.async {
            self.status = .KeysignFailed
            self.keysignError = errMessage
        }
    }

    func getCalculatedNetworkFee() -> (feeCrypto: String, feeFiat: String) {
        guard let keysignPayload else { return (.empty, .empty) }
        return gasViewModel.getCalculatedNetworkFee(payload: keysignPayload)
    }
}
