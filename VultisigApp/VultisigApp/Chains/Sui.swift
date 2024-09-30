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
        print("Coin ticker is SUI")
        
        guard case .Sui(let referenceGasPrice, let coins) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("Failed to get SUI transaction information from RPC")
        }
        print("Reference Gas Price: \(referenceGasPrice)")
        print("Coins:")
        for coin in coins {
            print("  \(coin)")
        }
        
        guard let toAddress = AnyAddress(string: keysignPayload.toAddress, coin: .sui) else {
            throw HelperError.runtimeError("Failed to parse 'to' address")
        }
        print("To Address: \(toAddress.description)")
        
        let suiCoins = coins.map { coinDict -> SuiObjectRef in
            var obj = SuiObjectRef()
            obj.objectID = coinDict["objectID"] ?? ""
            obj.version = UInt64(coinDict["version"] ?? "0") ?? 0
            obj.objectDigest = coinDict["objectDigest"] ?? ""
            print("Mapped SuiObjectRef:")
            print("  objectID: \(obj.objectID)")
            print("  version: \(obj.version)")
            print("  objectDigest: \(obj.objectDigest)")
            print("  balance: \(coinDict["balance"] ?? "")")
            return obj
        }
        print("Sui Coins:")
        for coin in suiCoins {
            print("  objectID: \(coin.objectID), version: \(coin.version), objectDigest: \(coin.objectDigest)")
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
        print("Signing Input:")
        print("  paySui:")
        print("    inputCoins:")
        for coin in input.paySui.inputCoins {
            print("      objectID: \(coin.objectID), version: \(coin.version), objectDigest: \(coin.objectDigest)")
        }
        print("    recipients: \(input.paySui.recipients)")
        print("    amounts: \(input.paySui.amounts)")
        print("  signer: \(input.signer)")
        print("  gasBudget: \(input.gasBudget)")
        print("  referenceGasPrice: \(input.referenceGasPrice)")
        
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
        print("Pre-Signing Image Hash: \(hash)")
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
        print("Public Key Data: \(pubkeyData.hexString)")
        
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)
        let hashes = TransactionCompiler.preImageHashes(coinType: .sui, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedData: hashes)
        let preSigningOutputDataBlake2b = Hash.blake2b(data: preSigningOutput.data, size: 32)
        print("Pre-Signing Output Data (Blake2b): \(preSigningOutputDataBlake2b.hexString)")
        
        let allSignatures = DataVector()
        let publicKeys = DataVector()
        let signatureProvider = SignatureProvider(signatures: signatures)
        let signature = signatureProvider.getSignature(preHash: preSigningOutputDataBlake2b)
        print("Signature: \(signature.hexString)")
        
        let isVerified = publicKey.verify(signature: signature, message: preSigningOutputDataBlake2b)
        print("Signature verification result: \(isVerified)")
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
        
        print("Signing Output:")
        print("  unsignedTx: \(output.unsignedTx)")
        print("  signature: \(output.signature)")
        print("output.errorMessage: \(output.errorMessage)")
        
        let result = SignedTransactionResult(
            rawTransaction: output.unsignedTx,
            transactionHash: "",
            signature: output.signature
        )
        return result
    }
    
}
extension SuiObjectRef: CustomStringConvertible {
    public var description: String {
        return "SuiObjectRef(objectID: \(objectID), version: \(version), objectDigest: \(objectDigest))"
    }
}
