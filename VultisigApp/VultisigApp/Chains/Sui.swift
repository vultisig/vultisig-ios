//
//  Sui.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 23/04/24.
//

import Foundation
import Tss
import WalletCore
import BigInt

enum SuiHelper {
    
    static func getPreSignedInputData(keysignPayload: KeysignPayload) throws -> Data {
        guard keysignPayload.coin.chain.ticker == "SUI" else {
            throw HelperError.runtimeError("coin is not SUI")
        }
        
        guard case .Sui(let referenceGasPrice, let coins, let gasBudget) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("getPreSignedInputData fail to get SUI transaction information from RPC")
        }
        
        guard let toAddress = AnyAddress(string: keysignPayload.toAddress, coin: .sui) else {
            throw HelperError.runtimeError("fail to get to address")
        }
        
        guard !coins.isEmpty else {
            throw HelperError.runtimeError("No coins available for transaction")
        }
        
        if keysignPayload.coin.isNativeToken {
            
            // We expect an array like a JSON
            // [["objectDigest": "", "objectID": "", "version": ""]]
            // NOT key value pair object
            // [[["objectDigest": ""], ["objectID": ""], ["version": ""]]]
            let suiCoins = coins.filter { $0["coinType"]?.uppercased().contains(keysignPayload.coin.ticker.uppercased()) == true }.map {
                var obj = SuiObjectRef()
                obj.objectID = $0["objectID"] ?? .empty
                obj.version = UInt64($0["version"] ?? .zero) ?? UInt64.zero
                obj.objectDigest = $0["objectDigest"] ?? .empty
                return obj
            }
            
            guard !suiCoins.isEmpty else {
                throw HelperError.runtimeError("Native token transaction requires at least one SUI coin")
            }
            
            let input = SuiSigningInput.with {
                $0.paySui = SuiPaySui.with {
                    $0.inputCoins = suiCoins
                    $0.recipients = [toAddress.description]
                    $0.amounts = [UInt64(keysignPayload.toAmount)]
                }
                $0.signer = keysignPayload.coin.address
                $0.gasBudget = UInt64(gasBudget)
                $0.referenceGasPrice = UInt64(referenceGasPrice)
            }
            
            return try input.serializedData()
            
        } else {
            
            guard coins.count >= 2 else {
                throw HelperError.runtimeError("We must have at least one TOKEN and one SUI coin")
            }
            
            // We expect an array like a JSON
            // [["objectDigest": "", "objectID": "", "version": ""]]
            // NOT key value pair object
            // [[["objectDigest": ""], ["objectID": ""], ["version": ""]]]
            let suiCoins = coins.filter { $0["coinType"]?.uppercased().contains(keysignPayload.coin.ticker.uppercased()) == true }.map {
                var obj = SuiObjectRef()
                obj.objectID = $0["objectID"] ?? .empty
                obj.version = UInt64($0["version"] ?? .zero) ?? UInt64.zero
                obj.objectDigest = $0["objectDigest"] ?? .empty
                return obj
            }
            
            guard !suiCoins.isEmpty else {
                throw HelperError.runtimeError("Non-native token transaction requires the token to be present")
            }
            
            let suiObjectForGas = coins.filter { $0["coinType"]?.uppercased().contains("SUI") == true }.map {
                var obj = SuiObjectRef()
                obj.objectID = $0["objectID"] ?? .empty
                obj.version = UInt64($0["version"] ?? .zero) ?? UInt64.zero
                obj.objectDigest = $0["objectDigest"] ?? .empty
                return obj
            }
            
            guard !suiObjectForGas.isEmpty else {
                throw HelperError.runtimeError("Non-native token transaction requires at least one SUI coin for gas fees")
            }
            
            let input = SuiSigningInput.with {
                $0.pay = SuiPay.with {
                    $0.inputCoins = suiCoins
                    $0.recipients = [toAddress.description]
                    $0.amounts = [UInt64(keysignPayload.toAmount)]
                    
                    if let gasObject = suiObjectForGas.first {
                        $0.gas = gasObject
                    }
                }
                $0.signer = keysignPayload.coin.address
                $0.gasBudget = UInt64(gasBudget)
                $0.referenceGasPrice = UInt64(referenceGasPrice)
            }
            
            return try input.serializedData()
        }
        
    }
    
    static func getPreSignedImageHash(keysignPayload: KeysignPayload) throws -> [String] {
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)
        let hashes = TransactionCompiler.preImageHashes(coinType: .sui, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedBytes: hashes)
        if !preSigningOutput.errorMessage.isEmpty {
            throw HelperError.runtimeError(preSigningOutput.errorMessage)
        }
        return [Hash.blake2b(data: preSigningOutput.data, size: 32).hexString]
    }
    
    static func getSignedTransaction(keysignPayload: KeysignPayload,
                                     signatures: [String: TssKeysignResponse]) throws -> SignedTransactionResult {
        let coinHexPublicKey = keysignPayload.coin.hexPublicKey
        guard let pubkeyData = Data(hexString: coinHexPublicKey) else {
            throw HelperError.runtimeError("public key \(coinHexPublicKey) is invalid")
        }
        guard let publicKey = PublicKey(data: pubkeyData, type: .ed25519) else {
            throw HelperError.runtimeError("public key \(coinHexPublicKey) is invalid")
        }
        
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)
        let hashes = TransactionCompiler.preImageHashes(coinType: .sui, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedBytes: hashes)
        let preSigningOutputDataBlake2b = Hash.blake2b(data: preSigningOutput.data, size: 32)
        let allSignatures = DataVector()
        let publicKeys = DataVector()
        let signatureProvider = SignatureProvider(signatures: signatures)
        let signature = signatureProvider.getSignature(preHash: preSigningOutputDataBlake2b)
        
        guard publicKey.verify(signature: signature, message: preSigningOutputDataBlake2b) else {
            throw HelperError.runtimeError("SUI signature verification failed")
        }
        
        allSignatures.add(data: signature)
        publicKeys.add(data: pubkeyData)
        let compileWithSignature = TransactionCompiler.compileWithSignatures(coinType: .sui,
                                                                             txInputData: inputData,
                                                                             signatures: allSignatures,
                                                                             publicKeys: publicKeys)
        let output = try SuiSigningOutput(serializedBytes: compileWithSignature)
        let result = SignedTransactionResult(rawTransaction: output.unsignedTx, transactionHash: .empty, signature: output.signature)
        return result
    }
    
    static func getZeroSignedTransaction(keysignPayload: KeysignPayload) throws -> String {
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)
        let hashes = TransactionCompiler.preImageHashes(coinType: .sui, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedBytes: hashes)
        
        // Drop 3 first bytes which represents signature, they're added by WalletCore
        // but for simulations or blockaid is not required
        let tx = Data(preSigningOutput.data.dropFirst(3))

        return Base64.encode(data: tx)
    }
}
