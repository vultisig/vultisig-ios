//
//  Cardano.swift
//  VultisigApp
//
//  Created by AI Assistant
//

import Foundation
import Tss
import WalletCore
import BigInt

enum CardanoHelper {
    
    static func getPreSignedInputData(keysignPayload: KeysignPayload) throws -> Data {
        guard keysignPayload.coin.chain == .cardano else {
            throw HelperError.runtimeError("coin is not ADA")
        }
        
        guard case .UTXO(let byteFee, let sendMaxAmount) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("fail to get UTXO chain specific byte fee")
        }
        
        guard let toAddress = AnyAddress(string: keysignPayload.toAddress, coin: .cardano) else {
            throw HelperError.runtimeError("fail to get to address: \(keysignPayload.toAddress)")
        }
        
        // Prevent from accidentally sending all balance
        var safeGuardMaxAmount = false
        if let rawBalance = Int64(keysignPayload.coin.rawBalance),
           sendMaxAmount,
           rawBalance > 0,
           rawBalance == Int64(keysignPayload.toAmount) {
            safeGuardMaxAmount = true
        }
        
        // For Cardano, we don't use UTXOs from Blockchair since it doesn't support Cardano
        // Instead, we create a simplified input structure
        var input = CardanoSigningInput.with {
            $0.transferMessage = CardanoTransfer.with {
                $0.toAddress = keysignPayload.toAddress
                $0.changeAddress = keysignPayload.coin.address
                $0.amount = UInt64(keysignPayload.toAmount)
                $0.useMaxAmount = safeGuardMaxAmount
                //$0.forceFee = UInt64(byteFee)
            }
            $0.ttl = 1736265600 // Fixed TTL for testing (2025-01-07 16:00:00 UTC) - REPLACE WITH DYNAMIC VALUE LATER
            
            // TODO: Add memo as transaction metadata if provided
            // Cardano memo support requires investigation of WalletCore protobuf structure
            // to find the correct metadata field (e.g., auxiliaryData, metadata, etc.)
            if let memo = keysignPayload.memo, !memo.isEmpty {
                print("Cardano memo provided but not yet implemented: \(memo)")
            }
        }
        
        // Add UTXOs to the input
        for inputUtxo in keysignPayload.utxos {
            let utxo = CardanoTxInput.with {
                $0.outPoint = CardanoOutPoint.with {
                    $0.txHash = Data(hexString: inputUtxo.hash)!
                    $0.outputIndex = UInt64(inputUtxo.index)
                }
                $0.amount = UInt64(inputUtxo.amount)
                $0.address = keysignPayload.coin.address
            }
            input.utxos.append(utxo)
        }
        
        return try input.serializedData()
    }
    
    static func getPreSignedImageHash(keysignPayload: KeysignPayload) throws -> [String] {
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)
        let hashes = TransactionCompiler.preImageHashes(coinType: .cardano, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedBytes: hashes)
        if !preSigningOutput.errorMessage.isEmpty {
            throw HelperError.runtimeError(preSigningOutput.errorMessage)
        }
        return [preSigningOutput.dataHash.hexString]
    }
    
    static func getSignedTransaction(vaultHexPubKey: String,
                                     vaultHexChainCode: String,
                                     keysignPayload: KeysignPayload,
                                     signatures: [String: TssKeysignResponse]) throws -> SignedTransactionResult {
        
        // Create proper Cardano V2 extended key structure (128 bytes total)
        guard let spendingKeyData = Data(hexString: vaultHexPubKey) else {
            throw HelperError.runtimeError("public key \(vaultHexPubKey) is invalid")
        }
        guard let chainCodeData = Data(hexString: vaultHexChainCode) else {
            throw HelperError.runtimeError("chain code \(vaultHexChainCode) is invalid")
        }
        
        // Ensure we have 32-byte keys
        guard spendingKeyData.count == 32 else {
            throw HelperError.runtimeError("spending key must be 32 bytes, got \(spendingKeyData.count)")
        }
        guard chainCodeData.count == 32 else {
            throw HelperError.runtimeError("chain code must be 32 bytes, got \(chainCodeData.count)")
        }
        
        // Build 128-byte extended key following Cardano V2 specification
        var extendedKeyData = Data()
        extendedKeyData.append(spendingKeyData)     // 32 bytes: EdDSA spending key
        extendedKeyData.append(spendingKeyData)     // 32 bytes: EdDSA staking key (reuse spending key)
        extendedKeyData.append(chainCodeData)       // 32 bytes: Chain code
        extendedKeyData.append(chainCodeData)       // 32 bytes: Additional chain code
        
        // Verify we have correct 128-byte structure
        guard extendedKeyData.count == 128 else {
            throw HelperError.runtimeError("extended key must be 128 bytes, got \(extendedKeyData.count)")
        }
        
        // For signature verification, use the raw 32-byte EdDSA key (matching TSS output)
        guard let verificationKey = PublicKey(data: spendingKeyData, type: .ed25519) else {
            throw HelperError.runtimeError("failed to create EdDSA public key for verification")
        }
        
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)
        let hashes = TransactionCompiler.preImageHashes(coinType: .cardano, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedBytes: hashes)
        
        let allSignatures = DataVector()
        let publicKeys = DataVector()
        let signatureProvider = SignatureProvider(signatures: signatures)
        let signature = signatureProvider.getSignature(preHash: preSigningOutput.dataHash)
        
        // Verify signature using 32-byte key (matches TSS output)
        guard verificationKey.verify(signature: signature, message: preSigningOutput.dataHash) else {
            throw HelperError.runtimeError("Cardano signature verification failed")
        }
        
        allSignatures.add(data: signature)
        publicKeys.add(data: extendedKeyData) // Still use 128-byte for WalletCore transaction compilation
        
        let compileWithSignature = TransactionCompiler.compileWithSignatures(coinType: .cardano,
                                                                             txInputData: inputData,
                                                                             signatures: allSignatures,
                                                                             publicKeys: publicKeys)
        let output = try CardanoSigningOutput(serializedBytes: compileWithSignature)
        let result = SignedTransactionResult(rawTransaction: output.encoded.hexString, 
                                           transactionHash: output.txID.hexString)
        return result
    }
} 