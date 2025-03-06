//
//  Osmosis.swift
//  VultisigApp
//
//  Created by Enrique Souza 07/11/2024
//

import Foundation
import WalletCore
import Tss
import CryptoSwift

class TerraHelper {
    let coinType: CoinType
    let denom: String
    
    init(coinType:CoinType, denom: String){
        self.coinType = coinType
        self.denom = denom
    }
    
    static let GasLimit:UInt64 = 300000
    
    func getPreSignedInputData(keysignPayload: KeysignPayload) throws -> Data {
        
        guard case .Cosmos(let accountNumber, let sequence , let gas, _, _) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("fail to get account number and sequence")
        }
        
        guard let pubKeyData = Data(hexString: keysignPayload.coin.hexPublicKey) else {
            throw HelperError.runtimeError("invalid hex public key")
        }
        
        if keysignPayload.coin.isNativeToken
            || keysignPayload.coin.contractAddress.lowercased().starts(with: "ibc/")
            || keysignPayload.coin.contractAddress.lowercased().starts(with: "factory/")
        {
            
            let input = CosmosSigningInput.with {
                $0.publicKey = pubKeyData
                $0.signingMode = .protobuf
                $0.chainID = self.coinType.chainId
                $0.accountNumber = accountNumber
                $0.sequence = sequence
                $0.mode = .sync
                if let memo = keysignPayload.memo {
                    $0.memo = memo
                }
                $0.messages = [CosmosMessage.with {
                    $0.sendCoinsMessage = CosmosMessage.Send.with{
                        $0.fromAddress = keysignPayload.coin.address
                        $0.amounts = [CosmosAmount.with {
                            $0.denom = keysignPayload.coin.isNativeToken ? self.denom : keysignPayload.coin.contractAddress
                            $0.amount = String(keysignPayload.toAmount)
                        }]
                        $0.toAddress = keysignPayload.toAddress
                    }
                }]
                
                $0.fee = CosmosFee.with {
                    $0.gas = TerraHelper.GasLimit
                    $0.amounts = [CosmosAmount.with {
                        $0.denom = self.denom
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
                    $0.chainID = self.coinType.chainId
                    $0.accountNumber = accountNumber
                    $0.sequence = sequence
                    $0.mode = .sync

                    if let memo = keysignPayload.memo {
                        $0.memo = memo
                    }

                    $0.messages = [CosmosMessage.with {
                        $0.sendCoinsMessage = CosmosMessage.Send.with {
                            $0.fromAddress = keysignPayload.coin.address
                            $0.amounts = [CosmosAmount.with {
                                $0.denom = keysignPayload.coin.contractAddress
                                $0.amount = String(keysignPayload.toAmount)
                            }]
                            $0.toAddress = keysignPayload.toAddress
                        }
                    }]

                    $0.fee = CosmosFee.with {
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
                
                let wasmGenericMessage = CosmosMessage.WasmExecuteContractGeneric.with {
                    $0.senderAddress = fromAddr.description
                    $0.contractAddress = keysignPayload.coin.contractAddress.description
                    $0.executeMsg = """
                                    {"transfer": { "amount": "\(keysignPayload.toAmount)", "recipient": "\(keysignPayload.toAddress)" } }
                                    """
                }

                let message = CosmosMessage.with {
                    $0.wasmExecuteContractGeneric = wasmGenericMessage
                }
                               
                let fee = CosmosFee.with {
                    $0.gas = TerraHelper.GasLimit
                    $0.amounts = [CosmosAmount.with {
                        $0.amount = String(gas)
                        $0.denom = self.denom
                    }]
                }
                
                let input = CosmosSigningInput.with {
                    $0.signingMode = .protobuf;
                    $0.accountNumber = accountNumber
                    $0.chainID = self.coinType.chainId
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
    
    func getPreSignedImageHash(keysignPayload: KeysignPayload) throws -> [String] {
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)
        let hashes = TransactionCompiler.preImageHashes(coinType: self.coinType, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedBytes: hashes)
        if !preSigningOutput.errorMessage.isEmpty {
            throw HelperError.runtimeError(preSigningOutput.errorMessage)
        }
        return [preSigningOutput.dataHash.hexString]
    }
    
    func getSignedTransaction(vaultHexPubKey: String,
                              vaultHexChainCode: String,
                              keysignPayload: KeysignPayload,
                              signatures: [String: TssKeysignResponse]) throws -> SignedTransactionResult
    {
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)
        let signedTransaction = try getSignedTransaction(vaultHexPubKey: vaultHexPubKey, vaultHexChainCode: vaultHexChainCode, inputData: inputData, signatures: signatures)
        return signedTransaction
    }
    
    func getSignedTransaction(vaultHexPubKey: String,
                              vaultHexChainCode: String,
                              inputData: Data,
                              signatures: [String: TssKeysignResponse]) throws -> SignedTransactionResult
    {
        let cosmosPublicKey = PublicKeyHelper.getDerivedPubKey(hexPubKey: vaultHexPubKey, hexChainCode: vaultHexChainCode, derivePath: self.coinType.derivationPath())
        guard let pubkeyData = Data(hexString: cosmosPublicKey),
              let publicKey = PublicKey(data: pubkeyData, type: .secp256k1)
        else {
            throw HelperError.runtimeError("public key \(cosmosPublicKey) is invalid")
        }
        
        do {
            let hashes = TransactionCompiler.preImageHashes(coinType: self.coinType, txInputData: inputData)
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
            let compileWithSignature = TransactionCompiler.compileWithSignatures(coinType: self.coinType,
                                                                                 txInputData: inputData,
                                                                                 signatures: allSignatures,
                                                                                 publicKeys: publicKeys)
            let output = try CosmosSigningOutput(serializedBytes: compileWithSignature)
            let serializedData = output.serialized
            let sig = try JSONDecoder().decode(CosmosSignature.self, from: serializedData.data(using: .utf8) ?? Data())
            let result = SignedTransactionResult(rawTransaction: serializedData, transactionHash:sig.getTransactionHash())
            return result
        } catch {
            throw HelperError.runtimeError("fail to get signed transaction,error:\(error.localizedDescription)")
        }
    }
}
