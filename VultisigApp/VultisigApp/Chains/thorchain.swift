//
//  thorchain.swift
//  VultisigApp
//

import Foundation
import Tss
import WalletCore
import VultisigCommonData

enum THORChainHelper {
    
    static func getSwapPreSignedInputData(keysignPayload: KeysignPayload) throws -> Data {
        guard case .THORChain(let accountNumber, let sequence, _, _, _) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("fail to get account number, sequence, or fee")
        }
        guard let pubKeyData = Data(hexString: keysignPayload.coin.hexPublicKey) else {
            throw HelperError.runtimeError("invalid hex public key")
        }
        guard let swapPayload = keysignPayload.swapPayload else {
            throw HelperError.runtimeError("swap payload is missing")
        }
        
        guard let fromAddr = AnyAddress(string: keysignPayload.coin.address, coin: .thorchain) else {
            throw HelperError.runtimeError("\(keysignPayload.coin.address) is invalid")
        }
        
        var chainID = keysignPayload.coin.coinType.chainId
        if chainID != ThorchainService.shared.network && !ThorchainService.shared.network.isEmpty {
            chainID = ThorchainService.shared.network
        }
        let input = CosmosSigningInput.with {
            $0.chainID = chainID
            $0.publicKey = pubKeyData
            $0.accountNumber = accountNumber
            $0.sequence = sequence
            $0.mode = .sync
            $0.signingMode = .protobuf
            $0.messages = [CosmosMessage.with {
                $0.thorchainDepositMessage = CosmosMessage.THORChainDeposit.with {
                    $0.signer = fromAddr.data
                    $0.memo = keysignPayload.memo ?? ""
                    $0.coins = [TW_Cosmos_Proto_THORChainCoin.with {
                        $0.asset = TW_Cosmos_Proto_THORChainAsset.with {
                            $0.chain = "THOR"
                            $0.symbol = swapPayload.fromCoin.ticker.uppercased().replacingOccurrences(of: "X/", with: "")
                            $0.ticker = swapPayload.fromCoin.ticker.uppercased().replacingOccurrences(of: "X/", with: "")
                            $0.synth = false
                        }
                        $0.amount = String(swapPayload.fromAmount)
                        $0.decimals = Int64(swapPayload.fromCoin.decimals)
                    }]
                }
            }]
            $0.fee = CosmosFee.with {
                $0.gas = 20000000
            }
        }
        
        return try input.serializedData()
    }
    
    static func getPreSignedInputData(keysignPayload: KeysignPayload) throws -> Data {
        guard keysignPayload.coin.chain == .thorChain else {
            throw HelperError.runtimeError("coin is not RUNE")
        }
        guard let fromAddr = AnyAddress(string: keysignPayload.coin.address, coin: .thorchain) else {
            throw HelperError.runtimeError("\(keysignPayload.coin.address) is invalid")
        }
        guard case .THORChain(let accountNumber, let sequence, _, let isDeposit, let transactionTypeRawValue) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("fail to get account number, sequence, or fee")
        }
        guard let pubKeyData = Data(hexString: keysignPayload.coin.hexPublicKey) else {
            throw HelperError.runtimeError("invalid hex public key")
        }
        let coin = CoinType.thorchain
        var chainID = coin.chainId
        if chainID != ThorchainService.shared.network && !ThorchainService.shared.network.isEmpty {
            chainID = ThorchainService.shared.network
        }
                
        let transactionType = VSTransactionType(rawValue: transactionTypeRawValue) ?? .unspecified
        let message: CosmosMessage
        
        if isDeposit {
            // This should invoke the wasm contract for RUJI merge/unmerge
            if transactionType.isGenericWasmMessage {
                message = try CosmosMessage.with {
                    $0.wasmExecuteContractGeneric = try buildThorchainWasmGenericMessage(keysignPayload: keysignPayload, transactionType: transactionType)
                }
            } else {
                message = buildThorchainDepositMessage(keysignPayload: keysignPayload, fromAddress: fromAddr)
            }
            
        } else {
            if transactionType == .genericContract {
                message = try CosmosMessage.with {
                    $0.wasmExecuteContractGeneric =
                    try buildThorchainWasmGenericMessage(keysignPayload: keysignPayload, transactionType: transactionType)
                }
            } else {
                message = try buildThorchainSendMessage(keysignPayload: keysignPayload, fromAddress: fromAddr)
            }
        }
        
        let input = CosmosSigningInput.with {
            $0.publicKey = pubKeyData
            $0.signingMode = .protobuf
            $0.chainID = chainID
            $0.accountNumber = accountNumber
            $0.sequence = sequence
            $0.mode = .sync
            if let memo = keysignPayload.memo {
                $0.memo = memo
            }
            $0.messages = [message]
            $0.fee = CosmosFee.with {
                $0.gas = 20_000_000
            }
        }
        return try input.serializedData()
    }
    
    static func getPreSignedImageHash(keysignPayload: KeysignPayload) throws -> [String] {
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)
        let hashes = TransactionCompiler.preImageHashes(coinType: .thorchain, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedBytes: hashes)
        if !preSigningOutput.errorMessage.isEmpty {
            throw HelperError.runtimeError(preSigningOutput.errorMessage)
        }
        return [preSigningOutput.dataHash.hexString]
    }
    
    static func getSignedTransaction(
        vaultHexPubKey: String,
        vaultHexChainCode: String,
        keysignPayload: KeysignPayload,
        signatures: [String: TssKeysignResponse]
    ) throws -> SignedTransactionResult
    {
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)
        let signedTransaction = try getSignedTransaction(vaultHexPubKey: vaultHexPubKey, vaultHexChainCode: vaultHexChainCode, inputData: inputData, signatures: signatures)
        return signedTransaction
    }
    
    static func getSignedTransaction(
        vaultHexPubKey: String,
        vaultHexChainCode: String,
        inputData: Data,
        signatures: [String: TssKeysignResponse]
    ) throws -> SignedTransactionResult
    {
        let thorPublicKey = PublicKeyHelper.getDerivedPubKey(hexPubKey: vaultHexPubKey, hexChainCode: vaultHexChainCode, derivePath: CoinType.thorchain.derivationPath())
        guard let pubkeyData = Data(hexString: thorPublicKey),
              let publicKey = PublicKey(data: pubkeyData, type: .secp256k1)
        else {
            throw HelperError.runtimeError("public key \(thorPublicKey) is invalid")
        }
        
        do {
            let hashes = TransactionCompiler.preImageHashes(coinType: .thorchain, txInputData: inputData)
            let preSigningOutput = try TxCompilerPreSigningOutput(serializedBytes: hashes)
            let allSignatures = DataVector()
            let publicKeys = DataVector()
            let signatureProvider = SignatureProvider(signatures: signatures)
            let signature = signatureProvider.getSignatureWithRecoveryID(preHash: preSigningOutput.dataHash)
            guard publicKey.verify(signature: signature, message: preSigningOutput.dataHash) else {
                throw HelperError.runtimeError("fail to verify signature")
            }
            
            allSignatures.add(data: signature)
            publicKeys.add(data: pubkeyData)
            let compileWithSignature = TransactionCompiler.compileWithSignatures(coinType: .thorchain,
                                                                                 txInputData: inputData,
                                                                                 signatures: allSignatures,
                                                                                 publicKeys: publicKeys)
            let output = try CosmosSigningOutput(serializedBytes: compileWithSignature)
            let serializedData = output.serialized
            let sig = try JSONDecoder().decode(CosmosSignature.self, from: serializedData.data(using: .utf8) ?? Data())
            let result = SignedTransactionResult(rawTransaction: serializedData, transactionHash:sig.getTransactionHash())
            return result
        } catch {
            throw HelperError.runtimeError("fail to get signed ethereum transaction,error:\(error.localizedDescription)")
        }
    }
    
    private static func buildThorchainWasmGenericMessage(keysignPayload: KeysignPayload, transactionType: VSTransactionType) throws -> CosmosMessage.WasmExecuteContractGeneric {
        guard let fromAddr = AnyAddress(string: keysignPayload.coin.address, coin: CoinType.thorchain) else {
            throw HelperError.runtimeError("\(keysignPayload.coin.address) is invalid")
        }
        
        let wasmGenericMessage = try CosmosMessage.WasmExecuteContractGeneric.with {
            $0.senderAddress = fromAddr.description
            $0.contractAddress = keysignPayload.toAddress
            switch transactionType {
            case .thorMerge:
                guard let memo = keysignPayload.memo?.lowercased() else {
                    throw HelperError.runtimeError("Missing memo for \(transactionType.rawValue)")
                }
                
                $0.executeMsg = """
                    { "deposit": {} }
                    """
                $0.coins = [
                    CosmosAmount.with {
                        $0.denom = memo.replacingOccurrences(of: "merge:", with: "")
                        $0.amount = String(keysignPayload.toAmount)
                    }
                ]
            case .thorUnmerge:
                guard let memo = keysignPayload.memo?.lowercased() else {
                    throw HelperError.runtimeError("Missing memo for \(transactionType.rawValue)")
                }
                // Parse shares amount from memo format: "unmerge:token:shares"
                let memoComponents = memo.split(separator: ":")
                let sharesAmount = memoComponents.count == 3 ? String(memoComponents[2]) : "0"
                $0.executeMsg = """
                     { "withdraw": { "share_amount": "\(sharesAmount)" } }
                     """
            case .genericContract:
                guard let contractPayload = keysignPayload.wasmExecuteContractPayload else {
                    throw HelperError.runtimeError("Invalid empty WasmExecuteContractPayload")
                }
                
                let formattedMessage = contractPayload.executeMsg
                    .replacingOccurrences(of: "^\\{", with: "{ ", options: .regularExpression)
                    .replacingOccurrences(of: "\\}$", with: " }", options: .regularExpression)
                    .replacingOccurrences(of: ":", with: ": ")
                let coins = contractPayload.coins.map { coin in
                    CosmosAmount.with {
                        $0.denom = coin.contractAddress.lowercased()
                        $0.amount = String(keysignPayload.toAmount)
                    }
                }
                $0.executeMsg = formattedMessage
                $0.senderAddress = contractPayload.senderAddress
                $0.contractAddress = contractPayload.contractAddress
                $0.coins = coins
            default:
                throw HelperError.runtimeError("Invalid tx type for WasmGenericMessage: \(transactionType.rawValue)")
            }
        }
        
        return wasmGenericMessage
    }
    
    private static func buildThorchainDepositMessage(keysignPayload: KeysignPayload, fromAddress: AnyAddress) -> CosmosMessage {
        let symbol = getTicker(coin: keysignPayload.coin)
        let assetTicker = getTicker(coin: keysignPayload.coin)
        let coin = CosmosTHORChainCoin.with {
            $0.asset = TW_Cosmos_Proto_THORChainAsset.with {
                $0.chain = "THOR"
                $0.symbol = symbol
                $0.ticker = assetTicker
                $0.synth = false
            }
            if keysignPayload.toAmount > 0 {
                $0.amount = String(keysignPayload.toAmount)
                $0.decimals = Int64(keysignPayload.coin.decimals)
            }
        }
        
        return CosmosMessage.with {
            $0.thorchainDepositMessage = CosmosMessage.THORChainDeposit.with {
                $0.signer = fromAddress.data
                if let memo = keysignPayload.memo {
                    $0.memo = memo
                }
                $0.coins = [coin]
            }
        }
    }
    
    private static func buildThorchainSendMessage(keysignPayload: KeysignPayload, fromAddress: AnyAddress) throws -> CosmosMessage {
        guard let toAddress = AnyAddress(string: keysignPayload.toAddress, coin: .thorchain) else {
            throw HelperError.runtimeError("\(keysignPayload.toAddress) is invalid")
        }
        
        return CosmosMessage.with {
            $0.thorchainSendMessage = CosmosMessage.THORChainSend.with {
                $0.fromAddress = fromAddress.data
                $0.amounts = [CosmosAmount.with {
                    $0.denom = (keysignPayload.coin.isNativeToken ? keysignPayload.coin.ticker : keysignPayload.coin.contractAddress).lowercased()
                    $0.amount = String(keysignPayload.toAmount)
                }]
                $0.toAddress = toAddress.data
            }
        }
    }
    
    private static func getTicker(coin: Coin) -> String {
        coin.isNativeToken ? "RUNE" : coin.ticker.uppercased().replacingOccurrences(of: "X/", with: "")
    }
}

private extension VSTransactionType {
    var isGenericWasmMessage: Bool {
        isMergeOrUnMerge || self == .genericContract
    }
    
    var isMergeOrUnMerge: Bool {
        self == .thorMerge  || self == .thorUnmerge
    }
}
