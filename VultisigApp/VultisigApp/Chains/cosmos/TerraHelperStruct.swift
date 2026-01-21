//
//  TerraHelperStruct.swift
//  VultisigApp
//
//  Refactored to use struct (value type) instead of classes
//

import Foundation
import WalletCore
import Tss
import VultisigCommonData

struct TerraHelperStruct {
    static let GasLimit: UInt64 = 300000
    
    static func getPreSignedInputData(keysignPayload: KeysignPayload, chain: Chain) throws -> Data {
        guard case .Cosmos(let accountNumber, let sequence , let gas, _, _) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("fail to get account number and sequence")
        }
        
        guard let pubKeyData = Data(hexString: keysignPayload.coin.hexPublicKey) else {
            throw HelperError.runtimeError("invalid hex public key")
        }
        
        let coinType = chain.coinType
        let denom = "uluna"
        
        if
            let signDataMessages = try CosmosSignDataBuilder.getMessages(keysignPayload: keysignPayload),
            let signDataFee = try CosmosSignDataBuilder.getFee(keysignPayload: keysignPayload) {
            
            let input = CosmosSigningInput.with {
                $0.publicKey = pubKeyData
                $0.signingMode = CosmosSignDataBuilder.getSigningMode(keysignPayload: keysignPayload)
                $0.chainID = coinType.chainId
                $0.accountNumber = accountNumber
                $0.sequence = sequence
                $0.mode = .sync
                if let memo = signDataMessages.memo ?? keysignPayload.memo {
                    $0.memo = memo
                }
                $0.messages = signDataMessages.messages
                $0.fee = signDataFee
            }
            
            return try input.serializedData()
            
        } else if keysignPayload.coin.isNativeToken
                    || keysignPayload.coin.contractAddress.lowercased().starts(with: "ibc/")
                    || keysignPayload.coin.contractAddress.lowercased().starts(with: "factory/") {
            
            let input = CosmosSigningInput.with {
                $0.publicKey = pubKeyData
                $0.signingMode = .protobuf
                $0.chainID = coinType.chainId
                $0.accountNumber = accountNumber
                $0.sequence = sequence
                $0.mode = .sync
                if let memo = keysignPayload.memo {
                    $0.memo = memo
                }
                $0.messages = [WalletCore.CosmosMessage.with {
                    $0.sendCoinsMessage = WalletCore.CosmosMessage.Send.with {
                        $0.fromAddress = keysignPayload.coin.address
                        $0.amounts = [CosmosAmount.with {
                            $0.denom = keysignPayload.coin.isNativeToken ? denom : keysignPayload.coin.contractAddress
                            $0.amount = String(keysignPayload.toAmount)
                        }]
                        $0.toAddress = keysignPayload.toAddress
                    }
                }]
                
                $0.fee = WalletCore.CosmosFee.with {
                    $0.gas = GasLimit
                    $0.amounts = [CosmosAmount.with {
                        $0.denom = denom
                        $0.amount = String(gas)
                    }]
                }
            }
            
            return try input.serializedData()
            
        } else {
            
            if !keysignPayload.coin.contractAddress.contains("terra1") && !keysignPayload.coin.contractAddress.contains("ibc/") {
                
                let input = CosmosSigningInput.with {
                    $0.publicKey = pubKeyData
                    $0.signingMode = .protobuf
                    $0.chainID = coinType.chainId
                    $0.accountNumber = accountNumber
                    $0.sequence = sequence
                    $0.mode = .sync
                    
                    if let memo = keysignPayload.memo {
                        $0.memo = memo
                    }
                    
                    $0.messages = [WalletCore.CosmosMessage.with {
                        $0.sendCoinsMessage = WalletCore.CosmosMessage.Send.with {
                            $0.fromAddress = keysignPayload.coin.address
                            $0.amounts = [CosmosAmount.with {
                                $0.denom = keysignPayload.coin.contractAddress
                                $0.amount = String(keysignPayload.toAmount)
                            }]
                            $0.toAddress = keysignPayload.toAddress
                        }
                    }]
                    
                    $0.fee = WalletCore.CosmosFee.with {
                        $0.gas = 1000000
                        $0.amounts = [
                            CosmosAmount.with {
                                $0.denom = "uluna"
                                $0.amount = String(gas) // Base fee in uluna
                            },
                            CosmosAmount.with { // Additional tax in uusd
                                $0.denom = "uusd"
                                $0.amount = String(1000000) // Replace `taxAmount` with your specific tax value
                            }
                        ]
                    }
                    
                }
                
                return try input.serializedData()
                
            } else {
                
                // This is for WASM tokens
                
                guard let fromAddr = AnyAddress(string: keysignPayload.coin.address, coin: coinType) else {
                    throw HelperError.runtimeError("\(keysignPayload.coin.address) is invalid")
                }
                
                let wasmGenericMessage = WalletCore.CosmosMessage.WasmExecuteContractGeneric.with {
                    $0.senderAddress = fromAddr.description
                    $0.contractAddress = keysignPayload.coin.contractAddress.description
                    $0.executeMsg = """
                                    {"transfer": { "amount": "\(keysignPayload.toAmount)", "recipient": "\(keysignPayload.toAddress)" } }
                                    """
                }
                
                let message = WalletCore.CosmosMessage.with {
                    $0.wasmExecuteContractGeneric = wasmGenericMessage
                }
                
                let fee = WalletCore.CosmosFee.with {
                    $0.gas = GasLimit
                    $0.amounts = [CosmosAmount.with {
                        $0.amount = String(gas)
                        $0.denom = denom
                    }]
                }
                
                let input = CosmosSigningInput.with {
                    $0.signingMode = .protobuf
                    $0.accountNumber = accountNumber
                    $0.chainID = coinType.chainId
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
            
        }
    }
    
    static func getPreSignedImageHash(keysignPayload: KeysignPayload, chain: Chain) throws -> [String] {
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload, chain: chain)
        let coinType = chain.coinType
        let hashes = TransactionCompiler.preImageHashes(coinType: coinType, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedBytes: hashes)
        if !preSigningOutput.errorMessage.isEmpty {
            throw HelperError.runtimeError(preSigningOutput.errorMessage)
        }
        return [preSigningOutput.dataHash.hexString]
    }
    
    static func getSignedTransaction(keysignPayload: KeysignPayload,
                                     signatures: [String: TssKeysignResponse],
                                     chain: Chain) throws -> SignedTransactionResult {
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload, chain: chain)
        let signedTransaction = try getSignedTransaction(coinHexPublicKey: keysignPayload.coin.hexPublicKey, inputData: inputData, signatures: signatures, chain: chain)
        return signedTransaction
    }
    
    static func getSignedTransaction(coinHexPublicKey: String,
                                     inputData: Data,
                                     signatures: [String: TssKeysignResponse],
                                     chain: Chain) throws -> SignedTransactionResult {
        let coinType = chain.coinType
        guard let pubkeyData = Data(hexString: coinHexPublicKey),
              let publicKey = PublicKey(data: pubkeyData, type: .secp256k1)
        else {
            throw HelperError.runtimeError("public key \(coinHexPublicKey) is invalid")
        }
        
        do {
            let hashes = TransactionCompiler.preImageHashes(coinType: coinType, txInputData: inputData)
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
            let compileWithSignature = TransactionCompiler.compileWithSignatures(coinType: coinType,
                                                                                 txInputData: inputData,
                                                                                 signatures: allSignatures,
                                                                                 publicKeys: publicKeys)
            let output = try CosmosSigningOutput(serializedBytes: compileWithSignature)
            let serializedData = output.serialized
            let transactionHash = CosmosSerializedParser.getTransactionHash(from: serializedData)
            let result = SignedTransactionResult(rawTransaction: serializedData, transactionHash: transactionHash)
            return result
        } catch {
            throw HelperError.runtimeError("fail to get signed terra transaction,error:\(error.localizedDescription)")
        }
    }
}
