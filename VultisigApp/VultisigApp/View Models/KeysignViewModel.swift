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
        // Debug logging for Cardano
        if let keysignPayload = keysignPayload, keysignPayload.coin.chain == .cardano {
            print("=== KeysignViewModel.setData Debug ===")
            print("Chain: \(keysignPayload.coin.chain)")
            print("ChainType: \(keysignPayload.coin.chainType)")
            print("Expected signingKeyType: \(keysignPayload.coin.chain.signingKeyType)")
            print("Passed keysignType: \(keysignType)")
            print("Vault pubKeyECDSA: \(vault.pubKeyECDSA)")
            print("Vault pubKeyEdDSA: \(vault.pubKeyEdDSA)")
            print("Messages to sign: \(messagesToSign)")
            print("=====================================")
        }
        
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
        
        // Use the correct public key based on signing type
        let pubKeyForMessagePuller: String
        if keysignType == .EdDSA {
            pubKeyForMessagePuller = vault.pubKeyEdDSA
            if let keysignPayload = keysignPayload, keysignPayload.coin.chain == .cardano {
                print("Using EdDSA pubKey for MessagePuller: \(vault.pubKeyEdDSA)")
            }
        } else {
            pubKeyForMessagePuller = vault.pubKeyECDSA
            if let keysignPayload = keysignPayload, keysignPayload.coin.chain == .cardano {
                print("⚠️ WARNING: Using ECDSA pubKey for MessagePuller on Cardano!")
            }
        }
        
        self.messagePuller = MessagePuller(encryptionKeyHex: encryptionKeyHex, pubKey: pubKeyForMessagePuller, encryptGCM: isEncryptGCM)
        self.isInitiateDevice = isInitiateDevice
    }
    
    func getTransactionExplorerURL(txid: String) -> String {
        guard let keysignPayload else { return .empty }
        return Endpoint.getExplorerURL(chain: keysignPayload.coin.chain, txid: txid)
    }
    
    func getSwapProgressURL(txid: String) -> String? {
        switch keysignPayload?.swapPayload {
        case .thorchain:
            return Endpoint.getSwapProgressURL(txid: txid)
        case .mayachain:
            return Endpoint.getMayaSwapTracker(txid: txid)
        case .oneInch, .none:
            return nil
        }
    }
    func startKeysign() async {
        switch vault.libType {
        case .GG20,.none:
            await startKeysignGG20()
        case .DKLS:
            await startKeysignDKLS()
        }
    }
    
    func startKeysignDKLS() async {
        print("=== DKLS Keysign Started ===")
        print("Vault libType: \(vault.libType?.toString() ?? "nil")")
        if let keysignPayload = keysignPayload, keysignPayload.coin.chain == .cardano {
            print("🔵 Starting DKLS Keysign for Cardano")
            print("Chain: \(keysignPayload.coin.chain)")
            print("KeysignType: \(self.keysignType)")
            print("Messages to sign: \(self.messsageToSign)")
        }
        print("============================")
        
        let derivePath = TokensStore.Token.ethereum.coinType.derivationPath()
        
        do {
            switch self.keysignType {
            case .ECDSA:
                print("🔑 Starting DKLS ECDSA Keysign")
                status = .KeysignECDSA
                let dklsKeysign = DKLSKeysign(keysignCommittee: self.keysignCommittee,
                                              mediatorURL: self.mediatorURL,
                                              sessionID: self.sessionID,
                                              messsageToSign: self.messsageToSign,
                                              vault: self.vault,
                                              encryptionKeyHex: self.encryptionKeyHex,
                                              chainPath: keysignPayload?.coin.coinType.derivationPath() ?? derivePath,
                                              isInitiateDevice: self.isInitiateDevice)
                if let keysignPayload = keysignPayload, keysignPayload.coin.chain == .cardano {
                    print("⚠️ WARNING: Using DKLS ECDSA for Cardano - should be EdDSA!")
                }
                try await dklsKeysign.DKLSKeysignWithRetry()
                self.signatures = dklsKeysign.getSignatures()
                print("DKLS ECDSA signatures received: \(self.signatures.count)")
                if self.signatures.count == 0 {
                    throw HelperError.runtimeError("fail to sign transaction")
                }
            case .EdDSA:
                print("🔑 Starting DKLS EdDSA (Schnorr) Keysign")
                if let keysignPayload = keysignPayload, keysignPayload.coin.chain == .cardano {
                    print("✅ Correctly using DKLS EdDSA for Cardano")
                    print("Cardano chainPath: \(keysignPayload.coin.coinType.derivationPath())")
                }
                status = .KeysignEdDSA
                
                // Only use chainPath for Cardano - other EdDSA chains (Solana, Polkadot, Sui, Ton) use raw keys
                let chainPathForSchnorr: String?
                if let keysignPayload = keysignPayload, keysignPayload.coin.chain == .cardano {
                    chainPathForSchnorr = keysignPayload.coin.coinType.derivationPath()
                    print("Using chainPath for Cardano: \(chainPathForSchnorr!)")
                } else {
                    chainPathForSchnorr = nil
                    if let keysignPayload = keysignPayload {
                        print("Using nil chainPath for \(keysignPayload.coin.chain) (raw EdDSA key)")
                    }
                }
                
                let schnorrKeysign = SchnorrKeysign(keysignCommittee: self.keysignCommittee,
                                                    mediatorURL: self.mediatorURL,
                                                    sessionID: self.sessionID,
                                                    messsageToSign: self.messsageToSign,
                                                    vault: self.vault,
                                                    encryptionKeyHex: self.encryptionKeyHex,
                                                    chainPath: chainPathForSchnorr,
                                                    isInitiateDevice: self.isInitiateDevice)
                print("SchnorrKeysign object created, starting keysign...")
                try await schnorrKeysign.KeysignWithRetry()
                print("SchnorrKeysign completed, getting signatures...")
                self.signatures = schnorrKeysign.getSignatures()
                print("DKLS EdDSA signatures received: \(self.signatures.count)")
                if let keysignPayload = keysignPayload, keysignPayload.coin.chain == .cardano {
                    print("🔵 Cardano DKLS EdDSA signatures: \(self.signatures)")
                }
                if self.signatures.count == 0 {
                    throw HelperError.runtimeError("fail to sign transaction")
                }
            }
            print("✅ DKLS Keysign completed successfully, broadcasting transaction...")
            await broadcastTransaction()
            if let customMessagePayload {
                txid = customMessagePayload.message
            }
            status = .KeysignFinished
        } catch {
            print("=== DKLS Keysign Error ===")
            print("Error: \(error)")
            print("Error description: \(error.localizedDescription)")
            if let keysignPayload = keysignPayload, keysignPayload.coin.chain == .cardano {
                print("🔴 Cardano DKLS Keysign Error")
            }
            print("==========================")
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
                try await keysignOneMessageWithRetry(msg: msg,attempt: 1)
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
        
        // Debug logging for Cardano
        if let keysignPayload = keysignPayload, keysignPayload.coin.chain == .cardano {
            print("=== Cardano Keysign Debug ===")
            print("Chain: \(keysignPayload.coin.chain)")
            print("ChainType: \(keysignPayload.coin.chainType)")
            print("KeysignType: \(self.keysignType)")
            print("Expected KeyType: \(keysignPayload.coin.chain.signingKeyType)")
            print("Derivation Path: \(keysignPayload.coin.coinType.derivationPath())")
            print("Vault pubKeyECDSA: \(vault.pubKeyECDSA)")
            print("Vault pubKeyEdDSA: \(vault.pubKeyEdDSA)")
        }
        
        let msgHash = Utils.getMessageBodyHash(msg: msg)
        let keySignVerify = KeysignVerify(serverAddr: self.mediatorURL,
                                          sessionID: self.sessionID)
        var pubkey = ""
        switch self.keysignType {
        case .ECDSA:
            pubkey = vault.pubKeyECDSA
            if let keysignPayload = keysignPayload, keysignPayload.coin.chain == .cardano {
                print("⚠️  WARNING: Using ECDSA for Cardano - should be EdDSA!")
            }
        case .EdDSA:
            pubkey = vault.pubKeyEdDSA
            if let keysignPayload = keysignPayload, keysignPayload.coin.chain == .cardano {
                print("✅ Correctly using EdDSA for Cardano")
            }
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
            if keysignPayload.coin.chain == .cardano {
                print("Cardano derivation path: \(keysignPayload.coin.coinType.derivationPath())")
            }
        } else {
            // TODO: Should we use Ether as default derivationPath?
            keysignReq.derivePath = TokensStore.Token.ethereum.coinType.derivationPath()
            if let keysignPayload = keysignPayload, keysignPayload.coin.chain == .cardano {
                print("⚠️  WARNING: Using Ethereum derivation path for Cardano!")
            }
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
                if let keysignPayload = keysignPayload, keysignPayload.coin.chain == .cardano {
                    print("Setting ECDSA pubKey for Cardano: \(self.vault.pubKeyECDSA)")
                }
            case .EdDSA:
                keysignReq.pubKey = self.vault.pubKeyEdDSA
                self.status = .KeysignEdDSA
                if let keysignPayload = keysignPayload, keysignPayload.coin.chain == .cardano {
                    print("Setting EdDSA pubKey for Cardano: \(self.vault.pubKeyEdDSA)")
                }
            }
            if let service = self.tssService {
                print("=== TSS Keysign Request ===")
                print("LocalPartyKey: \(keysignReq.localPartyKey)")
                print("KeysignType: \(keysignType)")
                print("DerivePath: \(keysignReq.derivePath)")
                print("PubKey: \(keysignReq.pubKey)")
                print("MessageToSign: \(keysignReq.messageToSign)")
                print("Committee: \(keysignReq.keysignCommitteeKeys)")
                if let keysignPayload = keysignPayload, keysignPayload.coin.chain == .cardano {
                    print("🔵 Cardano TSS Request initiated")
                }
                print("============================")
                
                let resp = try await tssKeysign(service: service, req: keysignReq, keysignType: keysignType)
                
                print("=== TSS Keysign Response ===")
                print("Response received for message: \(msg)")
                print("R value: \(resp.r)")
                print("S value: \(resp.s)")
                print("R isEmpty: \(resp.r.isEmpty)")
                print("S isEmpty: \(resp.s.isEmpty)")
                if let keysignPayload = keysignPayload, keysignPayload.coin.chain == .cardano {
                    print("🔵 Cardano TSS Response received")
                }
                print("============================")
                
                if resp.r.isEmpty || resp.s.isEmpty {
                    print("❌ TSS Keysign failed: R or S value is empty")
                    throw TssKeysignError.keysignFail
                }
                self.signatures[msg] = resp
                print("✅ TSS Signature stored successfully for message: \(msg)")
                await keySignVerify.markLocalPartyKeysignComplete(message: msgHash, sig:resp)
            }
            
            self.messagePuller?.stop()
            try await Task.sleep(for: .seconds(1)) // backoff for 1 seconds , so other party can finish appropriately
        } catch {
            self.messagePuller?.stop()
            // Check whether the other party already have the signature
            print("=== TSS Keysign Error ===")
            print("Error: \(error)")
            print("Error description: \(error.localizedDescription)")
            print("Attempt: \(attempt)")
            print("Message: \(msg)")
            if let keysignPayload = keysignPayload, keysignPayload.coin.chain == .cardano {
                print("🔴 Cardano TSS Keysign Error")
            }
            print("=========================")
            logger.error("keysign failed, error:\(error.localizedDescription) , attempt:\(attempt)")
            
            let resp = await keySignVerify.checkKeySignComplete(message: msgHash)
            if resp != nil {
                print("✅ Found existing signature from other party")
                self.signatures[msg] = resp
                return
            } else {
                print("❌ No existing signature found from other parties")
            }
            
            if attempt < 3 {
                print("🔄 Retrying keysign (attempt \(attempt + 1))")
                logger.info("retry keysign")
                try await keysignOneMessageWithRetry(msg: msg, attempt: attempt + 1)
            } else {
                print("❌ Max retries reached, throwing error")
                throw error
            }
        }
    }
    
    func stopMessagePuller(){
        messagePuller?.stop()
    }
    
    func tssKeysign(service: TssServiceImpl, req: TssKeysignRequest, keysignType: KeyType) async throws -> TssKeysignResponse {
        print("=== TSS Service Call ===")
        print("KeysignType: \(keysignType)")
        print("Starting TSS task...")
        
        let t = Task.detached(priority: .high) {
            print("📞 Calling TSS service with \(keysignType)")
            switch keysignType {
            case .ECDSA:
                print("🔑 Executing ECDSA keysign")
                return try service.keysignECDSA(req)
            case .EdDSA:
                print("🔑 Executing EdDSA keysign")
                return try service.keysignEdDSA(req)
            }
        }
        
        do {
            let result = try await t.value
            print("✅ TSS task completed successfully")
            return result
        } catch {
            print("❌ TSS task failed with error: \(error)")
            print("Error description: \(error.localizedDescription)")
            throw error
        }
    }
    
    func getSignedTransaction(keysignPayload: KeysignPayload) throws -> SignedTransactionType {
        
        // TODO: Refactor into Signed transaction factory
        var signedTransactions: [SignedTransactionResult] = []
        
        if let approvePayload = keysignPayload.approvePayload {
            let swaps = THORChainSwaps(vaultHexPublicKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode)
            let transaction = try swaps.getSignedApproveTransaction(approvePayload: approvePayload, keysignPayload: keysignPayload, signatures: signatures)
            signedTransactions.append(transaction)
        }
        
        if let swapPayload = keysignPayload.swapPayload {
            let incrementNonce = keysignPayload.approvePayload != nil
            switch swapPayload {
            case .thorchain(let payload):
                let swaps = THORChainSwaps(vaultHexPublicKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode)
                let transaction = try swaps.getSignedTransaction(swapPayload: payload, keysignPayload: keysignPayload, signatures: signatures, incrementNonce: incrementNonce)
                signedTransactions.append(transaction)
                
            case .oneInch(let payload):
                switch keysignPayload.coin.chain {
                case .solana:
                    let swaps = SolanaSwaps(vaultHexPubKey: vault.pubKeyEdDSA)
                    let transaction = try swaps.getSignedTransaction(swapPayload: payload, keysignPayload: keysignPayload, signatures: signatures)
                    signedTransactions.append(transaction)
                default:
                    let swaps = OneInchSwaps(vaultHexPublicKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode)
                    let transaction = try swaps.getSignedTransaction(payload: payload, keysignPayload: keysignPayload, signatures: signatures, incrementNonce: incrementNonce)
                    signedTransactions.append(transaction)
                }
            case .mayachain:
                break // No op - Regular transaction with memo
            }
        }
        
        if let signedTransactionType = SignedTransactionType(transactions: signedTransactions) {
            return signedTransactionType
        }
        
        switch keysignPayload.coin.chain.chainType {
        case .UTXO:
            let utxoHelper = UTXOChainsHelper(coin: keysignPayload.coin.coinType, vaultHexPublicKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode)
            let transaction = try utxoHelper.getSignedTransaction(keysignPayload: keysignPayload, signatures: signatures)
            return .regular(transaction)
            
        case .Cardano:
            print("=== Calling CardanoHelper.getSignedTransaction ===")
            print("vaultHexPubKey: \(vault.pubKeyEdDSA)")
            print("vaultHexChainCode: \(vault.hexChainCode)")
            print("signatures count: \(signatures.count)")
            let transaction = try CardanoHelper.getSignedTransaction(vaultHexPubKey: vault.pubKeyEdDSA, vaultHexChainCode: vault.hexChainCode, keysignPayload: keysignPayload, signatures: signatures)
            print("CardanoHelper.getSignedTransaction completed successfully")
            print("rawTransaction: \(transaction.rawTransaction)")
            print("transactionHash: \(transaction.transactionHash)")
            return .regular(transaction)
        case .EVM:
            if keysignPayload.coin.isNativeToken {
                let helper = EVMHelper.getHelper(coin: keysignPayload.coin)
                let transaction = try helper.getSignedTransaction(vaultHexPubKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode, keysignPayload: keysignPayload, signatures: signatures)
                return .regular(transaction)
            } else {
                let helper = ERC20Helper.getHelper(coin: keysignPayload.coin)
                let transaction = try helper.getSignedTransaction(vaultHexPubKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode, keysignPayload: keysignPayload, signatures: signatures)
                return .regular(transaction)
            }
            
        case .THORChain:
            if keysignPayload.coin.chain == .thorChain {
                let transaction = try THORChainHelper.getSignedTransaction(vaultHexPubKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode, keysignPayload: keysignPayload, signatures: signatures)
                return .regular(transaction)
            } else if keysignPayload.coin.chain == .mayaChain {
                let transaction = try MayaChainHelper.getSignedTransaction(vaultHexPubKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode, keysignPayload: keysignPayload, signatures: signatures)
                return .regular(transaction)
            }
            
        case .Solana:
            let transaction = try SolanaHelper.getSignedTransaction(vaultHexPubKey: vault.pubKeyEdDSA, keysignPayload: keysignPayload, signatures: signatures)
            return .regular(transaction)
            
        case .Sui:
            let transaction = try SuiHelper.getSignedTransaction(vaultHexPubKey: vault.pubKeyEdDSA, keysignPayload: keysignPayload, signatures: signatures)
            return .regular(transaction)
            
        case .Polkadot:
            let transaction = try PolkadotHelper.getSignedTransaction(vaultHexPubKey: vault.pubKeyEdDSA, keysignPayload: keysignPayload, signatures: signatures)
            return .regular(transaction)
            
        case .Cosmos:
            if keysignPayload.coin.chain == .gaiaChain {
                let transaction = try ATOMHelper().getSignedTransaction(vaultHexPubKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode, keysignPayload: keysignPayload, signatures: signatures)
                return .regular(transaction)
            } else if keysignPayload.coin.chain == .kujira {
                let transaction = try KujiraHelper().getSignedTransaction(vaultHexPubKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode, keysignPayload: keysignPayload, signatures: signatures)
                return .regular(transaction)
            } else if keysignPayload.coin.chain == .dydx {
                let transaction = try DydxHelper().getSignedTransaction(vaultHexPubKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode, keysignPayload: keysignPayload, signatures: signatures)
                return .regular(transaction)
            } else if keysignPayload.coin.chain == .osmosis {
                let transaction = try OsmoHelper().getSignedTransaction(vaultHexPubKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode, keysignPayload: keysignPayload, signatures: signatures)
                return .regular(transaction)
            } else if keysignPayload.coin.chain == .terra {
                let transaction = try TerraHelper(coinType: .terraV2, denom: "uluna").getSignedTransaction(vaultHexPubKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode, keysignPayload: keysignPayload, signatures: signatures)
                return .regular(transaction)
            } else if keysignPayload.coin.chain == .terraClassic {
                let transaction = try TerraHelper(coinType: .terra, denom: "uluna").getSignedTransaction(vaultHexPubKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode, keysignPayload: keysignPayload, signatures: signatures)
                return .regular(transaction)
            } else if keysignPayload.coin.chain == .noble {
                let transaction = try NobleHelper().getSignedTransaction(vaultHexPubKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode, keysignPayload: keysignPayload, signatures: signatures)
                return .regular(transaction)
            } else if keysignPayload.coin.chain == .akash {
                let transaction = try AkashHelper().getSignedTransaction(vaultHexPubKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode, keysignPayload: keysignPayload, signatures: signatures)
                return .regular(transaction)
            }
            
            
        case .Ton:
            let transaction = try TonHelper.getSignedTransaction(vaultHexPubKey: vault.pubKeyEdDSA, keysignPayload: keysignPayload, signatures: signatures)
            return .regular(transaction)
        case .Ripple:
            let transaction = try RippleHelper.getSignedTransaction(vaultHexPubKey: vault.pubKeyECDSA,keysignPayload: keysignPayload, signatures: signatures, vault: vault)
            return .regular(transaction)
        case .Tron:
            let transaction = try TronHelper.getSignedTransaction(vaultHexPubKey: vault.pubKeyECDSA, keysignPayload: keysignPayload, signatures: signatures, vault: vault)
            return .regular(transaction)
        }
        
        throw HelperError.runtimeError("Unexpected error")
    }
    
    func broadcastTransaction() async {
        guard let keysignPayload else { return }
        
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
                case .thorChain:
                    let broadcastResult = await ThorchainService.shared.broadcastTransaction(jsonString: tx.rawTransaction)
                    switch broadcastResult {
                    case .success(let txHash):
                        self.txid = txHash
                        print("Transaction successful, hash: \(txHash)")
                    case .failure(let error):
                        throw error
                    }
                case .mayaChain:
                    let broadcastResult = await MayachainService.shared.broadcastTransaction(jsonString: tx.rawTransaction)
                    switch broadcastResult {
                    case .success(let txHash):
                        self.txid = txHash
                        print("Transaction successful, hash: \(txHash)")
                    case .failure(let error):
                        throw error
                    }
                case .ethereum, .avalanche,.arbitrum, .bscChain, .base, .optimism, .polygon, .polygonV2, .blast, .cronosChain, .zksync,.ethereumSepolia:
                    let service = try EvmServiceFactory.getService(forChain: keysignPayload.coin.chain)
                    self.txid = try await service.broadcastTransaction(hex: tx.rawTransaction)
                case .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .dash, .zcash:
                    let chainName = keysignPayload.coin.chain.name.lowercased()
                    UTXOTransactionsService.broadcastTransaction(chain: chainName, signedTransaction: tx.rawTransaction) { result in
                        switch result {
                        case .success(let transactionHash):
                            self.txid = transactionHash
                        case .failure(let error):
                            self.handleBroadcastError(error: error, transactionType: transactionType)
                        }
                    }
                case .cardano:
                    // TODO: Implement proper Cardano broadcast service
                    // For now, use UTXOTransactionsService as fallback until CardanoService.broadcastTransaction is implemented
                    let chainName = keysignPayload.coin.chain.name.lowercased()
                    UTXOTransactionsService.broadcastTransaction(chain: chainName, signedTransaction: tx.rawTransaction) { result in
                        switch result {
                        case .success(let transactionHash):
                            self.txid = transactionHash
                        case .failure(let error):
                            self.handleBroadcastError(error: error, transactionType: transactionType)
                        }
                    }
                case .gaiaChain:
                    let broadcastResult = await GaiaService.shared.broadcastTransaction(jsonString: tx.rawTransaction)
                    switch broadcastResult {
                    case .success(let hash):
                        self.txid = hash
                    case .failure(let err):
                        throw err
                    }
                case .kujira:
                    let broadcastResult = await KujiraService.shared.broadcastTransaction(jsonString: tx.rawTransaction)
                    switch broadcastResult {
                    case .success(let hash):
                        self.txid = hash
                    case .failure(let err):
                        throw err
                    }
                case .osmosis:
                    let broadcastResult = await OsmosisService.shared.broadcastTransaction(jsonString: tx.rawTransaction)
                    switch broadcastResult {
                    case .success(let hash):
                        self.txid = hash
                    case .failure(let err):
                        throw err
                    }
                case .dydx:
                    let broadcastResult = await DydxService.shared.broadcastTransaction(jsonString: tx.rawTransaction)
                    switch broadcastResult {
                    case .success(let hash):
                        self.txid = hash
                    case .failure(let err):
                        throw err
                    }
                case .terra:
                    let broadcastResult = await TerraService.shared.broadcastTransaction(jsonString: tx.rawTransaction)
                    switch broadcastResult {
                    case .success(let hash):
                        self.txid = hash
                    case .failure(let err):
                        throw err
                    }
                case .terraClassic:
                    let broadcastResult = await TerraClassicService.shared.broadcastTransaction(jsonString: tx.rawTransaction)
                    switch broadcastResult {
                    case .success(let hash):
                        self.txid = hash
                    case .failure(let err):
                        throw err
                    }
                case .noble:
                    let broadcastResult = await NobleService.shared.broadcastTransaction(jsonString: tx.rawTransaction)
                    switch broadcastResult {
                    case .success(let hash):
                        self.txid = hash
                    case .failure(let err):
                        throw err
                    }
                case .solana:
                    self.txid = try await SolanaService.shared.sendSolanaTransaction(encodedTransaction: tx.rawTransaction) ?? .empty
                case .sui:
                    self.txid = try await SuiService.shared.executeTransactionBlock(unsignedTransaction: tx.rawTransaction, signature: tx.signature ?? .empty)
                case .polkadot:
                    self.txid = try await PolkadotService.shared.broadcastTransaction(hex: tx.rawTransaction)
                    
                case .ton:
                    let base64Hash = try await TonService.shared.broadcastTransaction(tx.rawTransaction)
                    self.txid = Data(base64Encoded: base64Hash)?.hexString ?? ""
                case .ripple:
                    self.txid = try await RippleService.shared.broadcastTransaction(tx.rawTransaction)
                case .akash:
                    let broadcastResult = await AkashService.shared.broadcastTransaction(jsonString: tx.rawTransaction)
                    switch broadcastResult {
                    case .success(let hash):
                        self.txid = hash
                    case .failure(let err):
                        throw err
                    }
                    
                case .tron:
                    
                    let broadcastResult = await TronService.shared.broadcastTransaction(jsonString: tx.rawTransaction)
                    
                    switch broadcastResult {
                    case .success(let txHash):
                        self.txid = txHash
                        print("Transaction successful, hash: \(txHash)")
                    case .failure(let error):
                        throw error
                    }
                }
                
            case .regularWithApprove(let approve, let transaction):
                let service = try EvmServiceFactory.getService(forChain: keysignPayload.coin.chain)
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
    
    func handleBroadcastError(error: Error, transactionType: SignedTransactionType) {
        var errMessage: String = ""
        switch error {
        case HelperError.runtimeError(let errDetail):
            errMessage = "Failed to broadcast transaction,\(errDetail)"
        case RpcEvmServiceError.rpcError(let code, let message):
            print("code:\(code), message:\(message)")
            if message == "already known" || message == "replacement transaction underpriced"{
                print("the transaction already broadcast,code:\(code)")
                self.txid = transactionType.transactionHash
                return
            }
        default:
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
}
