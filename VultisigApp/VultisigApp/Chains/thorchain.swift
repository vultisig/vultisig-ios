//
//  thorchain.swift
//  VultisigApp
//

import Foundation
import Tss
import WalletCore

enum THORChainHelper {
    
    static func getSwapPreSignedInputData(keysignPayload: KeysignPayload) throws -> Data {
        guard case .THORChain(let accountNumber, let sequence, _, _) = keysignPayload.chainSpecific else {
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
        guard case .THORChain(let accountNumber, let sequence, _, let isDeposit) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("fail to get account number, sequence, or fee")
        }
        guard let pubKeyData = Data(hexString: keysignPayload.coin.hexPublicKey) else {
            throw HelperError.runtimeError("invalid hex public key")
        }
        let coin = CoinType.thorchain
        
        var thorChainCoin = TW_Cosmos_Proto_THORChainCoin()
        var message = [CosmosMessage()]
        
        var chainID = coin.chainId
        if chainID != ThorchainService.shared.network && !ThorchainService.shared.network.isEmpty {
            chainID = ThorchainService.shared.network
        }
        
        if isDeposit {
            
            // This should invoke the wasm contract for RUJI merge/unmerge
            if keysignPayload.memo?.lowercased().hasPrefix("merge:") == true || 
               keysignPayload.memo?.lowercased().hasPrefix("unmerge:") == true {
                // it's a merge or unmerge
                
                let mergeToken: String = keysignPayload.memo?.lowercased()
                    .replacingOccurrences(of: "merge:", with: "")
                    .replacingOccurrences(of: "unmerge:", with: "") ?? ""
                
                // This is for WASM tokens
                
                guard let fromAddr = AnyAddress(string: keysignPayload.coin.address, coin: .thorchain) else {
                    throw HelperError.runtimeError("\(keysignPayload.coin.address) is invalid")
                }
                
                let executeMsg: String
                if keysignPayload.memo?.lowercased().hasPrefix("unmerge:") == true {
                    // Parse shares amount from memo
                    let sharesAmount = keysignPayload.memo?.lowercased()
                        .replacingOccurrences(of: "unmerge:", with: "")
                        .replacingOccurrences(of: mergeToken.lowercased() + ":", with: "") ?? "0"
                    executeMsg = """
                    { "redeem": { "share_amount": "\(sharesAmount)" } }
                    """
                } else {
                    executeMsg = """
                    { "deposit": {} }
                    """
                }
                
                let wasmGenericMessage = CosmosMessage.WasmExecuteContractGeneric.with {
                    $0.senderAddress = fromAddr.description
                    $0.contractAddress = keysignPayload.toAddress.description
                    $0.executeMsg = executeMsg
                    $0.coins = keysignPayload.memo?.lowercased().hasPrefix("unmerge:") == true ? [] : [
                        TW_Cosmos_Proto_Amount.with {
                            $0.denom = mergeToken.lowercased() // "THOR.KUJI".lowercased()
                            $0.amount = String(keysignPayload.toAmount)
                        }
                    ]
                }
                
                let message = CosmosMessage.with {
                    $0.wasmExecuteContractGeneric = wasmGenericMessage
                }
                
                let fee = CosmosFee.with {
                    $0.gas = 20000000
                }
                
                let input = CosmosSigningInput.with {
                    $0.signingMode = .protobuf;
                    $0.accountNumber = accountNumber
                    $0.chainID = chainID
                    if let memo = keysignPayload.memo {
                        $0.memo = memo
                    }
                    $0.sequence = sequence
                    $0.messages = [message]
                    $0.fee = fee
                    $0.publicKey = pubKeyData
                    $0.mode = .sync
                }
                
                return try input.serializedData()
                
            }
            
            
            thorChainCoin = TW_Cosmos_Proto_THORChainCoin.with {
                $0.asset = TW_Cosmos_Proto_THORChainAsset.with {
                    $0.chain = "THOR"
                    $0.symbol = keysignPayload.coin.isNativeToken ? "RUNE" : keysignPayload.coin.ticker.uppercased().replacingOccurrences(of: "X/", with: "")
                    $0.ticker = keysignPayload.coin.isNativeToken ? "RUNE" : keysignPayload.coin.ticker.uppercased().replacingOccurrences(of: "X/", with: "")
                    $0.synth = false
                }
                if keysignPayload.toAmount > 0 {
                    $0.amount = String(keysignPayload.toAmount)
                    $0.decimals = 8
                }
            }
            message = [CosmosMessage.with {
                $0.thorchainDepositMessage = CosmosMessage.THORChainDeposit.with {
                    $0.signer = fromAddr.data
                    $0.memo = keysignPayload.memo ?? ""
                    $0.coins = [thorChainCoin]
                }
            }]
        } else {
            guard let toAddress = AnyAddress(string: keysignPayload.toAddress, coin: .thorchain) else {
                throw HelperError.runtimeError("\(keysignPayload.toAddress) is invalid")
            }
            
            message = [CosmosMessage.with {
                $0.thorchainSendMessage = CosmosMessage.THORChainSend.with {
                    $0.fromAddress = fromAddr.data
                    $0.amounts = [CosmosAmount.with {
                        $0.denom = keysignPayload.coin.isNativeToken ? "rune" : keysignPayload.coin.contractAddress
                        $0.amount = String(keysignPayload.toAmount)
                    }]
                    $0.toAddress = toAddress.data
                }
            }]
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
            $0.messages = message
            $0.fee = CosmosFee.with {
                $0.gas = 20000000
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
    
    static func getSignedTransaction(vaultHexPubKey: String,
                                     vaultHexChainCode: String,
                                     keysignPayload: KeysignPayload,
                                     signatures: [String: TssKeysignResponse]) throws -> SignedTransactionResult
    {
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)
        let signedTransaction = try getSignedTransaction(vaultHexPubKey: vaultHexPubKey, vaultHexChainCode: vaultHexChainCode, inputData: inputData, signatures: signatures)
        return signedTransaction
    }
    
    static func getSignedTransaction(vaultHexPubKey: String,
                                     vaultHexChainCode: String,
                                     inputData: Data,
                                     signatures: [String: TssKeysignResponse]) throws -> SignedTransactionResult
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
}
