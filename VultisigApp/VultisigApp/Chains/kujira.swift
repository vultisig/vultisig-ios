//
//  kujira.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 17/04/2024.
//

import Foundation
import WalletCore
import Tss
import CryptoSwift

class KujiraHelper {
    let coinType: CoinType
    let denom: String
    
    init(coinType:CoinType, denom: String){
        self.coinType = coinType
        self.denom = denom
    }
    
    static let kujiraGasLimit:UInt64 = 200000
    
    func getPreSignedInputData(keysignPayload: KeysignPayload) throws -> Data {
        guard case .Cosmos(let accountNumber, let sequence , let gas, _, let ibc) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("getPreSignedInputData: fail to get account number and sequence")
        }
        guard let pubKeyData = Data(hexString: keysignPayload.coin.hexPublicKey) else {
            throw HelperError.runtimeError("getPreSignedInputData: invalid hex public key")
        }
        let coin = self.coinType
        
        if keysignPayload.coin.isNativeToken {
            
            let input = CosmosSigningInput.with {
                $0.publicKey = pubKeyData
                $0.signingMode = .protobuf
                $0.chainID = coin.chainId
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
                            $0.denom = "ukuji"
                            $0.amount = String(keysignPayload.toAmount)
                        }]
                        $0.toAddress = keysignPayload.toAddress
                    }
                }]
                
                $0.fee = CosmosFee.with {
                    $0.gas = KujiraHelper.kujiraGasLimit
                    $0.amounts = [CosmosAmount.with {
                        $0.denom = "ukuji"
                        $0.amount = String(gas)
                    }]
                }
            }
            
            return try input.serializedData()
            
        } else {
                        
            if keysignPayload.coin.contractAddress.lowercased().starts(with: "ibc/") {
                
                guard let splittedPath = ibc?.path.split(separator: "/") else {
                    throw HelperError.runtimeError("It must have a valid IBC path")
                }
                guard let sourcePort = splittedPath.first?.description else {
                    throw HelperError.runtimeError("It must have a valid source port")
                }
                guard let sourceChannel = splittedPath.last?.description else {
                    throw HelperError.runtimeError("It must have a valid source channel")
                }
                
                guard (ibc?.baseDenom) != nil else {
                    throw HelperError.runtimeError("It must have a valid IBC base denom")
                }
                
                let timeoutAndBlockHeight = ibc?.height?.split(separator: "_")
                                
                guard let blockHeight = timeoutAndBlockHeight?.first, blockHeight != "0", let blockHeight = UInt64(blockHeight), blockHeight > 0 else {
                    throw HelperError.runtimeError("It must have a valid blockHeight")
                }
                
                guard let timeoutInNanoSeconds = timeoutAndBlockHeight?.last, let timeoutInNanoSeconds = UInt64(timeoutInNanoSeconds), blockHeight > 0 else {
                    throw HelperError.runtimeError("It must have a valid blockHeight")
                }
                
                let transferMessage = CosmosMessage.Transfer.with {
                    $0.sourcePort = sourcePort
                    $0.sourceChannel = sourceChannel
                    $0.sender = keysignPayload.coin.address.description
                    $0.receiver = keysignPayload.toAddress
                    $0.token = CosmosAmount.with {
                        $0.amount = String(keysignPayload.toAmount)
                        $0.denom = keysignPayload.coin.contractAddress // We must send to the IBC/{hash}
                    }
                    
                    $0.timeoutHeight = CosmosHeight.with {
                        $0.revisionNumber = 1
                        $0.revisionHeight = blockHeight + 1000
                    }
                    
                    $0.timeoutTimestamp = timeoutInNanoSeconds
                }
                
                let message = CosmosMessage.with {
                    $0.transferTokensMessage = transferMessage
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
        
        throw HelperError.runtimeError("It must be a native token or a valid IBC token")
    }
    
    func getPreSignedImageHash(keysignPayload: KeysignPayload) throws -> [String] {
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)
        let hashes = TransactionCompiler.preImageHashes(coinType: coinType, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedData: hashes)
        if !preSigningOutput.errorMessage.isEmpty {
            print("Error getPreSignedImageHash: \(preSigningOutput.errorMessage)")
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
            let preSigningOutput = try TxCompilerPreSigningOutput(serializedData: hashes)
            let allSignatures = DataVector()
            let publicKeys = DataVector()
            let signatureProvider = SignatureProvider(signatures: signatures)
            let signature = signatureProvider.getSignatureWithRecoveryID(preHash: preSigningOutput.dataHash)
            guard publicKey.verify(signature: signature, message: preSigningOutput.dataHash) else {
                print("getSignedTransaction signature is invalid")
                throw HelperError.runtimeError("fail to verify signature")
            }
            
            allSignatures.add(data: signature)
            publicKeys.add(data: pubkeyData)
            let compileWithSignature = TransactionCompiler.compileWithSignatures(coinType: self.coinType,
                                                                                 txInputData: inputData,
                                                                                 signatures: allSignatures,
                                                                                 publicKeys: publicKeys)
            let output = try CosmosSigningOutput(serializedData: compileWithSignature)
            
            if output.errorMessage.count > 0 {
                print("getSignedTransaction Error message: \(output.errorMessage)")
            }
            
            let serializedData = output.serialized
            let sig = try JSONDecoder().decode(CosmosSignature.self, from: serializedData.data(using: .utf8) ?? Data())
            let result = SignedTransactionResult(rawTransaction: serializedData, transactionHash:sig.getTransactionHash())
            return result
        } catch {
            throw HelperError.runtimeError("fail to get signed transaction,error:\(error.localizedDescription)")
        }
    }
}
