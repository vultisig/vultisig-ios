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
    
    static let defaultFeeInSui: BigInt = 1000  // Example fee, adjust as necessary
    
    static func getPreSignedInputData(keysignPayload: KeysignPayload) throws -> Data {
        guard keysignPayload.coin.chain.ticker == "SUI" else {
            throw HelperError.runtimeError("coin is not SUI")
        }
        
        guard case .Sui(let referenceGasPrice, let coins) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("Failed to get SUI transaction information from RPC")
        }
        
        guard let toAddress = AnyAddress(string: keysignPayload.toAddress, coin: .sui) else {
            throw HelperError.runtimeError("Failed to parse 'to' address")
        }
        
        let suiCoins = coins.map { coinDict -> SuiObjectRef in
            var obj = SuiObjectRef()
            obj.objectID = coinDict["objectID"] ?? ""
            obj.version = UInt64(coinDict["version"] ?? "0") ?? 0
            obj.objectDigest = coinDict["objectDigest"] ?? ""
            return obj
        }
       
        let input = SuiSigningInput.with {
            $0.paySui = SuiPaySui.with {
                $0.inputCoins = suiCoins
                $0.recipients = [toAddress.description]
                $0.amounts = [UInt64(keysignPayload.toAmount)]
            }
            $0.signer = keysignPayload.coin.address
            $0.gasBudget = 3000000
            $0.referenceGasPrice = UInt64(referenceGasPrice)
        }
        
        return try input.serializedData()
    }
    
    static func getPreSignedImageHash(keysignPayload: KeysignPayload) throws -> [String] {
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)
        let hashes = TransactionCompiler.preImageHashes(coinType: .sui, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedData: hashes)
        if !preSigningOutput.errorMessage.isEmpty {
            throw HelperError.runtimeError(preSigningOutput.errorMessage)
        }
        let hash = Hash.blake2b(data: preSigningOutput.data, size: 32).hexString
        return [hash]
    }
    
    static func getSignedTransaction(vaultHexPubKey: String,
                                     vaultHexChainCode: String,
                                     keysignPayload: KeysignPayload,
                                     signatures: [String: TssKeysignResponse]) throws -> SignedTransactionResult {
        guard let pubkeyData = Data(hexString: vaultHexPubKey) else {
            throw HelperError.runtimeError("Invalid public key \(vaultHexPubKey)")
        }
        guard let publicKey = PublicKey(data: pubkeyData, type: .ed25519) else {
            throw HelperError.runtimeError("Invalid public key \(vaultHexPubKey)")
        }
        
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)
        let hashes = TransactionCompiler.preImageHashes(coinType: .sui, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedData: hashes)
        let preSigningOutputDataBlake2b = Hash.blake2b(data: preSigningOutput.data, size: 32)
        
        let allSignatures = DataVector()
        let publicKeys = DataVector()
        let signatureProvider = SignatureProvider(signatures: signatures)
        let signature = signatureProvider.getSignature(preHash: preSigningOutputDataBlake2b)
        
        let isVerified = publicKey.verify(signature: signature, message: preSigningOutputDataBlake2b)
        guard isVerified else {
            throw HelperError.runtimeError("SUI signature verification failed")
        }
        
        allSignatures.add(data: signature)
        publicKeys.add(data: pubkeyData)
        let compileWithSignature = TransactionCompiler.compileWithSignatures(
            coinType: .sui,
            txInputData: inputData,
            signatures: allSignatures,
            publicKeys: publicKeys
        )
        let output = try SuiSigningOutput(serializedData: compileWithSignature)
        let result = SignedTransactionResult(
            rawTransaction: output.unsignedTx,
            transactionHash: "",
            signature: output.signature
        )
        return result
    }
}
