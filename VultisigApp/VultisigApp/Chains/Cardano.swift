//
//  Cardano.swift
//  VultisigApp
//
//  Created by Enrique Souza on 11.06.2025.
//

import Foundation
import Tss
import WalletCore
import BigInt

enum CardanoHelper {
    
    // MARK: - Helper Functions
    

    
    static func getPreSignedInputData(keysignPayload: KeysignPayload) throws -> Data {
        guard keysignPayload.coin.chain == .cardano else {
            throw HelperError.runtimeError("coin is not ADA")
        }
        
        guard case .Cardano(let byteFee, let sendMaxAmount, let ttl) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("fail to get Cardano chain specific parameters")
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
            }
            $0.ttl = ttl
            
            // TODO: Implement memo support when WalletCore adds Cardano metadata support
            // Investigation shows WalletCore Signer.cpp already reserves space for auxiliary_data (line 305)
            // but protobuf definitions (Cardano.proto) don't expose metadata/memo fields yet
            // Would need: CardanoAuxiliaryData, CardanoTransactionMetadata, CardanoTransactionMetadataValue types
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
        
        // Use the helper function to create extended key
        let extendedKeyData = try CoinFactory.createCardanoExtendedKey(spendingKeyHex: vaultHexPubKey, chainCodeHex: vaultHexChainCode)
        
        // For signature verification, use the raw 32-byte EdDSA key (matching TSS output)
        guard let spendingKeyData = Data(hexString: vaultHexPubKey),
              let verificationKey = PublicKey(data: spendingKeyData, type: .ed25519) else {
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
