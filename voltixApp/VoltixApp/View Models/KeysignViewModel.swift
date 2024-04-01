//
//  KeysignViewModel.swift
//  VoltixApp
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
}

@MainActor
class KeysignViewModel: ObservableObject {
    private let logger = Logger(subsystem: "keysign", category: "tss")
    @Published var status: KeysignStatus = .CreatingInstance
    @Published var keysignError: String = ""
    @Published var signatures = [String: TssKeysignResponse]()
    @Published var etherScanService = EtherScanService.shared
    @Published var avaxScanService = AvalancheService.shared
    @Published var txid: String = ""
    
    private var tssService: TssServiceImpl? = nil
    private var tssMessenger: TssMessengerImpl? = nil
    private var stateAccess: LocalStateAccessorImpl? = nil
    private var messagePuller = MessagePuller()
    private let bscService = BSCService.shared
    
    var keysignCommittee: [String]
    var mediatorURL: String
    var sessionID: String
    var keysignType: KeyType
    var messsageToSign: [String]
    var vault: Vault
    var keysignPayload: KeysignPayload?
    
    init() {
        self.keysignCommittee = []
        self.mediatorURL = ""
        self.sessionID = ""
        self.vault = Vault(name: "tempory")
        self.keysignType = .ECDSA
        self.messsageToSign = []
        self.keysignPayload = nil
    }
    
    func setData(keysignCommittee: [String],
                 mediatorURL: String,
                 sessionID: String,
                 keysignType: KeyType,
                 messagesToSign: [String],
                 vault: Vault,
                 keysignPayload: KeysignPayload?) {
        self.keysignCommittee = keysignCommittee
        self.mediatorURL = mediatorURL
        self.sessionID = sessionID
        self.keysignType = keysignType
        self.messsageToSign = messagesToSign
        self.vault = vault
        self.keysignPayload = keysignPayload
    }
    func getTransactionExplorerURL(txid: String) -> String{
        guard let keysignPayload else {
            return ""
        }
        return Endpoint.getExplorerURL(chainTicker: keysignPayload.coin.chain.ticker, txid: txid)
    }
    func startKeysign() async {
        defer {
            self.messagePuller.stop()
        }
        for msg in self.messsageToSign {
            logger.info("signing message:\(msg)")
            let msgHash = Utils.getMessageBodyHash(msg: msg)
            self.tssMessenger = TssMessengerImpl(mediatorUrl: self.mediatorURL, sessionID: self.sessionID, messageID: msgHash)
            self.stateAccess = LocalStateAccessorImpl(vault: self.vault)
            var err: NSError?
            // keysign doesn't need to recreate preparams
            self.tssService = TssNewService(self.tssMessenger, self.stateAccess, false, &err)
            if let err {
                self.logger.error("Failed to create TSS instance, error: \(err.localizedDescription)")
                self.keysignError = err.localizedDescription
                self.status = .KeysignFailed
                return
            }
            guard let service = self.tssService else {
                self.logger.error("tss service instance is nil")
                self.status = .KeysignFailed
                return
            }
            
            self.messagePuller.pollMessages(mediatorURL: self.mediatorURL,
                                            sessionID: self.sessionID,
                                            localPartyKey: self.vault.localPartyID,
                                            tssService: service,
                                            messageID: msgHash)
            
            let keysignReq = TssKeysignRequest()
            keysignReq.localPartyKey = self.vault.localPartyID
            keysignReq.keysignCommitteeKeys = self.keysignCommittee.joined(separator: ",")
            if let keysignPayload {
                let coinType = keysignPayload.coin.getCoinType()
                if let coinType {
                    keysignReq.derivePath = coinType.derivationPath()
                } else {
                    self.logger.error("don't support this coin type")
                    self.status = .KeysignFailed
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
                case .EdDSA:
                    keysignReq.pubKey = self.vault.pubKeyEdDSA
                    self.status = .KeysignEdDSA
                }
                if let service = self.tssService {
                    let resp = try await tssKeysign(service: service, req: keysignReq, keysignType: keysignType)
                    self.signatures[msg] = resp
                }
                self.messagePuller.stop()
                try await Task.sleep(for: .seconds(1)) // backoff for 1 seconds , so other party can finish appropriately
            } catch {
                self.logger.error("fail to do keysign,error:\(error.localizedDescription)")
                self.keysignError = error.localizedDescription
                self.status = .KeysignFailed
                return
            }
            
        }
        await self.broadcastTransaction()
        self.status = .KeysignFinished
        
    }
    func stopMessagePuller(){
        self.messagePuller.stop()
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
    
    func broadcastTransaction() async {
        if let keysignPayload {
            if keysignPayload.swapPayload != nil {
                let swaps = THORChainSwaps(vaultHexPublicKey: vault.pubKeyECDSA, vaultHexChainCode: self.vault.hexChainCode)
                let result = swaps.getSignedTransaction(keysignPayload: keysignPayload, signatures: self.signatures)
                switch result {
                case .success(let tx):
                    print(tx)
                case .failure(let err):
                    print(err.localizedDescription)
                }
                return
            }
            switch keysignPayload.coin.chain.chainType {
            case .UTXO:
                let chainName = keysignPayload.coin.chain.name.lowercased()
                
                guard let coinType = keysignPayload.coin.getCoinType() else {
                    print("Coin type not found on Wallet Core")
                    return
                }
                
                let utxoHelper = UTXOChainsHelper(coin: coinType, vaultHexPublicKey: vault.pubKeyECDSA, vaultHexChainCode: self.vault.hexChainCode)
                
                let result = utxoHelper.getSignedTransaction(keysignPayload: keysignPayload, signatures: self.signatures)
                
                switch result {
                case .success(let tx):
                    print("Broadcasting UTXO transaction from \(chainName): \(tx)")
                    UTXOTransactionsService.broadcastTransaction(chain: chainName, signedTransaction: tx) { result in
                        switch result {
                        case .success(let transactionHash):
                            self.txid = transactionHash
                            print("Transaction successfully broadcasted. Hash: \(transactionHash)")
                        case .failure(let error):
                            self.handleBroadcastError(err: error)
                        }
                    }
                case .failure(let err):
                    self.handleHelperError(err: err)
                }
                
            case .EVM:
                if keysignPayload.coin.chain.name == Chain.Ethereum.name {
                    if keysignPayload.coin.isNativeToken {
                        let result = EVMHelper.getEthereumHelper().getSignedTransaction(vaultHexPubKey: self.vault.pubKeyECDSA, vaultHexChainCode: self.vault.hexChainCode, keysignPayload: keysignPayload, signatures: self.signatures)
                        switch result {
                        case .success(let tx):
                            do {
                                self.txid = try await self.etherScanService.broadcastTransaction(hex: tx)
                            } catch {
                                self.handleBroadcastError(err: error)
                            }
                            
                        case .failure(let err):
                            self.handleHelperError(err: err)
                        }
                    } else {
                        // It should work for all ERC20
                        let result = ERC20Helper.getEthereumERC20Helper().getSignedTransaction(vaultHexPubKey: self.vault.pubKeyECDSA, vaultHexChainCode: self.vault.hexChainCode, keysignPayload: keysignPayload, signatures: self.signatures)
                        
                        switch result {
                        case .success(let tx):
                            do {
                                self.txid = try await self.etherScanService.broadcastTransaction(hex: tx)
                            } catch {
                                self.handleBroadcastError(err: error)
                            }
                        case .failure(let err):
                            self.handleHelperError(err: err)
                        }
                    }
                } else if keysignPayload.coin.chain.name == Chain.BSCChain.name {
                    if keysignPayload.coin.isNativeToken {
                        let result = EVMHelper.getBSCHelper().getSignedTransaction(vaultHexPubKey: self.vault.pubKeyECDSA, vaultHexChainCode: self.vault.hexChainCode, keysignPayload: keysignPayload, signatures: self.signatures)
                        switch result {
                        case .success(let tx):
                            do {
                                self.txid = try await self.bscService.broadcastTransaction(hex: tx)
                            } catch {
                                self.handleBroadcastError(err: error)
                            }
                            
                        case .failure(let err):
                            self.handleHelperError(err: err)
                        }
                    } else {
                        // It should work for all BEP20
                        let result = ERC20Helper.getBSCBEP20Helper().getSignedTransaction(vaultHexPubKey: self.vault.pubKeyECDSA, vaultHexChainCode: self.vault.hexChainCode, keysignPayload: keysignPayload, signatures: self.signatures)
                        
                        switch result {
                        case .success(let tx):
                            do {
                                self.txid = try await  self.bscService.broadcastTransaction(hex: tx)
                            } catch {
                                self.handleBroadcastError(err: error)
                            }
                        case .failure(let err):
                            self.handleHelperError(err: err)
                        }
                    }
                }else if keysignPayload.coin.chain.name == Chain.Avalache.name {
                    if keysignPayload.coin.isNativeToken {
                        let result = EVMHelper.getAvaxHelper().getSignedTransaction(vaultHexPubKey: self.vault.pubKeyECDSA, vaultHexChainCode: self.vault.hexChainCode, keysignPayload: keysignPayload, signatures: self.signatures)
                        switch result {
                        case .success(let tx):
                            do {
                                print("AVAX signed tx \(tx)")
                                self.txid = try await self.avaxScanService.broadcastTransaction(hex: tx)
                            } catch {
                                self.handleBroadcastError(err: error)
                            }
                            
                        case .failure(let err):
                            self.handleHelperError(err: err)
                        }
                    } else {
                        // It should work for all ERC20
                        let result = ERC20Helper.getAvaxERC20Helper().getSignedTransaction(vaultHexPubKey: self.vault.pubKeyECDSA, vaultHexChainCode: self.vault.hexChainCode, keysignPayload: keysignPayload, signatures: self.signatures)
                        
                        switch result {
                        case .success(let tx):
                            do {
                                self.txid = try await self.avaxScanService.broadcastTransaction(hex: tx)
                            } catch {
                                self.handleBroadcastError(err: error)
                            }
                        case .failure(let err):
                            self.handleHelperError(err: err)
                        }
                    }
                }
            case .THORChain:
                let result = THORChainHelper.getSignedTransaction(vaultHexPubKey: self.vault.pubKeyECDSA, vaultHexChainCode: self.vault.hexChainCode, keysignPayload: keysignPayload, signatures: self.signatures)
                switch result {
                case .success(let tx):
                    let broadcastResult = await ThorchainService.shared.broadcastTransaction(jsonString: tx)
                    switch broadcastResult {
                    case .success(let txHash):
                        self.txid = txHash
                        print("Transaction successful, hash: \(txHash)")
                    case .failure(let error):
                        self.handleBroadcastError(err: error)
                    }
                    
                case .failure(let err):
                    self.handleHelperError(err: err)
                }
            case .Solana:
                let result = SolanaHelper.getSignedTransaction(vaultHexPubKey: self.vault.pubKeyEdDSA, vaultHexChainCode: self.vault.hexChainCode, keysignPayload: keysignPayload, signatures: self.signatures)
                switch result {
                case .success(let tx):
                    await SolanaService.shared.sendSolanaTransaction(encodedTransaction: tx)
                    self.txid = SolanaService.shared.transactionResult ?? ""
                case .failure(let err):
                    self.handleHelperError(err: err)
                }
            default:
                self.logger.error("unsupported coin:\(keysignPayload.coin.ticker)")
            }
        }
    }
    func handleBroadcastError(err: Error){
        var errMessage: String
        switch err{
        case HelperError.runtimeError(let errDetail):
            errMessage = "Failed to broadcast transaction,\(errDetail)"
        default:
            errMessage = "Failed to broadcast transaction,error:\(err.localizedDescription)"
        }
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
    
    func handleBitcoinTransactionError(err: UTXOTransactionError) {
        switch err {
        case .invalidURL:
            print("Invalid URL.")
        case .httpError(let statusCode):
            print("HTTP Error with status code: \(statusCode).")
        case .apiError(let message):
            print("API Error: \(message)")
        case .unexpectedResponse:
            print("Unexpected response from the server.")
        case .unknown(let unknownError):
            print("An unknown error occurred: \(unknownError.localizedDescription)")
        }
    }
}
