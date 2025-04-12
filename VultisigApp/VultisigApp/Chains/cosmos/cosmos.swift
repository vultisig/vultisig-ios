//
//  cosmos.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 19/11/24.
//

import Foundation
import WalletCore
import Tss
import CryptoSwift
import VultisigCommonData

class CosmosHelper {
    var coinType: CoinType
    var denom: String
    var gasLimit: UInt64
    
    init(coinType:CoinType, denom: String, gasLimit: UInt64){
        self.coinType = coinType
        self.denom = denom
        self.gasLimit = gasLimit
    }
    
    func getSwapPreSignedInputData(keysignPayload: KeysignPayload, signingInput: CosmosSigningInput) throws -> Data {
        guard case .Cosmos(let accountNumber, let sequence,let gas, _, _) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("fail to get account number and sequence")
        }
        guard let pubKeyData = Data(hexString: keysignPayload.coin.hexPublicKey) else {
            throw HelperError.runtimeError("invalid hex public key")
        }
        var input = signingInput
        input.publicKey = pubKeyData
        input.accountNumber = accountNumber
        input.sequence = sequence
        input.mode = .sync
        
        input.fee = CosmosFee.with {
            $0.gas = self.gasLimit
            $0.amounts = [CosmosAmount.with {
                $0.denom = self.denom
                $0.amount = String(gas)
            }]
        }
        // memo has been set
        // deposit message has been set
        return try input.serializedData()
    }
    
    
    func getPreSignedInputData(keysignPayload: KeysignPayload) throws -> Data {
        guard case .Cosmos(let accountNumber, let sequence , let gas, let transactionTypeRawValue, let ibcDenomTrace) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("getPreSignedInputData: fail to get account number and sequence")
        }
        guard let pubKeyData = Data(hexString: keysignPayload.coin.hexPublicKey) else {
            throw HelperError.runtimeError("getPreSignedInputData: invalid hex public key")
        }
        let coin = self.coinType
        
        
        var transactionType: VSTransactionType = .unspecified
        if let vsTransactionType = VSTransactionType(rawValue: transactionTypeRawValue) {
            transactionType = vsTransactionType
        }
        
        if transactionType == .ibcTransfer {
            
            var memo = ""
            let splitedMemo = keysignPayload.memo?.split(separator: ":");
            if splitedMemo?.count == 0 {
                throw HelperError.runtimeError("To send IBC transaction, memo should be specified")
            }
            
            let sourceChannel = splitedMemo?[1] ?? ""
            
            if splitedMemo?.count == 4 {
                memo = String(splitedMemo?[3] ?? "")
            }
            
            let timeouts = ibcDenomTrace?.height?.split(separator: "_") ?? []
            
            let timeout = UInt64(timeouts.last ?? "0") ?? 0
            
            let transferMessage = CosmosMessage.Transfer.with {
                $0.sourcePort = "transfer"
                $0.sourceChannel = String(sourceChannel)
                $0.sender = keysignPayload.coin.address
                $0.receiver = String(keysignPayload.toAddress)
                $0.token = CosmosAmount.with {
                    $0.denom = keysignPayload.coin.isNativeToken ? self.denom : keysignPayload.coin.contractAddress
                    $0.amount = String(keysignPayload.toAmount)
                }
                $0.timeoutHeight = CosmosHeight.with {
                    $0.revisionNumber = 0
                    $0.revisionHeight = 0
                }
                $0.timeoutTimestamp = timeout
            }
            
            
            let input = CosmosSigningInput.with {
                $0.publicKey = pubKeyData
                $0.signingMode = .protobuf
                $0.chainID = coin.chainId
                $0.accountNumber = accountNumber
                $0.sequence = sequence
                $0.mode = .sync
                if !memo.isEmpty {
                    $0.memo = memo
                }
                $0.messages = [CosmosMessage.with { $0.transferTokensMessage = transferMessage }]
                
                $0.fee = CosmosFee.with {
                    $0.gas = self.gasLimit
                    $0.amounts = [CosmosAmount.with {
                        $0.denom = self.denom
                        $0.amount = String(gas)
                    }]
                }
            }
            
            return try input.serializedData()
            
        }
        
        if keysignPayload.coin.isNativeToken
            || keysignPayload.coin.contractAddress.lowercased().starts(with: "ibc/")
            || keysignPayload.coin.contractAddress.lowercased().starts(with: "factory/")
            || keysignPayload.coin.contractAddress.lowercased().starts(with: "u")
        {
            
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
                            $0.denom = keysignPayload.coin.isNativeToken ? self.denom : keysignPayload.coin.contractAddress
                            $0.amount = String(keysignPayload.toAmount)
                        }]
                        $0.toAddress = keysignPayload.toAddress
                    }
                }]
                
                $0.fee = CosmosFee.with {
                    $0.gas = self.gasLimit
                    $0.amounts = [CosmosAmount.with {
                        $0.denom = self.denom
                        $0.amount = String(gas)
                    }]
                }
            }
            
            return try input.serializedData()
            
        }
        
        throw HelperError.runtimeError("It must be a native token or a valid IBC token")
    }
    
    func getPreSignedImageHash(keysignPayload: KeysignPayload) throws -> [String] {
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)
        let hashes = TransactionCompiler.preImageHashes(coinType: coinType, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedBytes: hashes)
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
            let preSigningOutput = try TxCompilerPreSigningOutput(serializedBytes: hashes)
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
            let output = try CosmosSigningOutput(serializedBytes: compileWithSignature)
            
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
