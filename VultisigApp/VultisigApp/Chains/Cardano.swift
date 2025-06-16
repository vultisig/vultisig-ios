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

/*
 Cardano UTXO Validation & Send Max Recommendations
 
 This implementation provides comprehensive validation for Cardano transactions with focus on:
 
 1. MINIMUM SEND AMOUNT: ≥ 1.4 ADA (Alonzo era real-world requirement)
 2. SUFFICIENT BALANCE: Balance must cover send amount + fees
 3. CHANGE/TROCO VALIDATION: If change exists, it must be ≥ 1.4 ADA OR exactly 0
 4. SEND MAX RECOMMENDATIONS: Proactively suggest "Send Max" to avoid UTXO issues
 
 Key Benefits:
 - Prevents transaction failures due to invalid change amounts
 - User-friendly error messages with actionable solutions
 - Proactive recommendations for low balance scenarios
 - Follows real-world Cardano Alonzo era requirements (based on transaction evidence)
 
 Example scenarios:
 ✅ Send 2 ADA, Balance 5 ADA, Fee 0.17 ADA → Change 2.83 ADA (valid)
 ✅ Send 3.2 ADA, Balance 5 ADA, Fee 0.17 ADA → Change 1.63 ADA (valid)
 ❌ Send 4.0 ADA, Balance 5 ADA, Fee 0.17 ADA → Change 0.83 ADA (invalid - below 1.4 ADA)
 ✅ Send Max 4.83 ADA, Balance 5 ADA, Fee 0.17 ADA → Change 0 ADA (valid)
 */

enum CardanoHelper {
    
    /*
     Cardano minimum UTXO value requirement (Alonzo Era) - UPDATED BASED ON REAL EVIDENCE
     Official Alonzo documentation shows:
     - utxoEntrySize = 38 words × coinsPerUTxOWord (34,482) = 1,310,316 lovelace ≈ 1.31 ADA
     - Real-world evidence from transactions shows failures below ~1.4 ADA
     Using conservative 1.4 ADA to prevent transaction failures
     https://cardano-ledger.readthedocs.io/en/latest/explanations/min-utxo-alonzo.html
     */
    static let defaultMinUTXOValue: BigInt = 1_400_000 // 1.4 ADA in lovelaces (real-world tested)
    
    /// Validate Cardano transaction meets UTXO requirements for both send amount and remaining balance
    /// 
    /// Cardano UTXO Validation Rules:
    /// 1. Send amount must be ≥ 1.4 ADA (minUTXO)
    /// 2. Total balance must cover send amount + fees  
    /// 3. If there's change/troco, it must be ≥ 1.4 ADA OR exactly 0 (no change)
    ///
    /// Examples:
    /// - Send 2 ADA, Balance 5 ADA, Fee 0.17 ADA → Change 2.83 ADA ✅ (valid)
    /// - Send 4.0 ADA, Balance 5 ADA, Fee 0.17 ADA → Change 0.83 ADA ❌ (invalid - change < 1.4)
    /// - Send 4.83 ADA, Balance 5 ADA, Fee 0.17 ADA → Change 0 ADA ✅ (valid - no change)
    ///
    /// - Parameters:
    ///   - sendAmount: Amount to send in lovelaces
    ///   - totalBalance: Total available balance in lovelaces  
    ///   - estimatedFee: Estimated transaction fee in lovelaces
    /// - Returns: Tuple with validation result and error message if any
    static func validateUTXORequirements(sendAmount: BigInt, totalBalance: BigInt, estimatedFee: BigInt) -> (isValid: Bool, errorMessage: String?) {
        let minUTXOValue = defaultMinUTXOValue
        
        // 1. Check send amount meets minimum
        if sendAmount < minUTXOValue {
            let minAmountADA = Double(minUTXOValue) / 1_000_000.0
            return (false, "Minimum send amount is \(minAmountADA) ADA. Cardano requires this to prevent spam.")
        }
        
        // 2. Check sufficient balance
        let totalNeeded = sendAmount + estimatedFee
        if totalBalance < totalNeeded {
            let maxSendADA = Double(totalBalance - estimatedFee) / 1_000_000.0
            
            // Recommend Send Max for insufficient balance
            if totalBalance > estimatedFee && maxSendADA > 0 {
                return (false, "Insufficient balance. 💡 Try 'Send Max' to send \(maxSendADA) ADA instead.")
            } else {
                let availableADA = Double(totalBalance) / 1_000_000.0
                return (false, "Insufficient balance (\(availableADA) ADA). You need more ADA to complete this transaction.")
            }
        }
        
        // 3. Check remaining balance (change) meets minimum UTXO requirement
        let remainingBalance = totalBalance - sendAmount - estimatedFee
        if remainingBalance > 0 && remainingBalance < minUTXOValue {
            let sendAllAmount = Double(totalBalance - estimatedFee) / 1_000_000.0
            
            // Always recommend Send Max for change issues - simplest solution
            return (false, "This amount would leave too little change. 💡 Try 'Send Max' (\(sendAllAmount) ADA) to avoid this issue.")
        }
        
        return (true, nil)
    }
    
    /// Suggest valid send amounts when UTXO validation fails
    /// - Parameters:
    ///   - totalBalance: Total available balance in lovelaces
    ///   - estimatedFee: Estimated transaction fee in lovelaces
    /// - Returns: Tuple with suggested minimum and maximum valid amounts in ADA format
    static func suggestValidSendAmounts(totalBalance: BigInt, estimatedFee: BigInt) -> (minSendADA: Double, maxSendADA: Double) {
        let minUTXOValue = defaultMinUTXOValue
        
        // Minimum send amount is always the minUTXO value
        let minSendAmount = minUTXOValue
        
        // Maximum send amount scenarios:
        // 1. Send all (no change): totalBalance - estimatedFee
        // 2. Send leaving exactly minUTXO as change: totalBalance - estimatedFee - minUTXOValue
        
        let sendAllAmount = totalBalance - estimatedFee
        let sendLeavingMinChangeAmount = totalBalance - estimatedFee - minUTXOValue
        
        // The maximum valid send is the higher of these two valid options
        let maxSendAmount = max(sendAllAmount, sendLeavingMinChangeAmount)
        
        let minSendADA = Double(minSendAmount) / 1_000_000.0
        let maxSendADA = Double(maxSendAmount) / 1_000_000.0
        
        return (minSendADA, max(minSendADA, maxSendADA))
    }
    
    /// Check if balance is low and should recommend "Send Max" to avoid UTXO issues
    /// - Parameters:
    ///   - totalBalance: Total available balance in lovelaces
    ///   - estimatedFee: Estimated transaction fee in lovelaces
    /// - Returns: Tuple indicating if balance is low and recommendation message
    static func shouldRecommendSendMax(totalBalance: BigInt, estimatedFee: BigInt) -> (shouldRecommend: Bool, message: String?) {
        let minUTXOValue = defaultMinUTXOValue
        let maxSendAmount = totalBalance - estimatedFee
        
        // Balance is considered "low" if total balance is less than 3.5 ADA
        // This helps avoid change issues with the 1.4 ADA minimum
        let lowBalanceThreshold: BigInt = 3_500_000 // 3.5 ADA in lovelaces
        
        if totalBalance <= lowBalanceThreshold && maxSendAmount > 0 {
            let maxSendADA = Double(maxSendAmount) / 1_000_000.0
            
            return (true, "💡 Low balance detected. Consider 'Send Max' (\(maxSendADA) ADA) to avoid change issues.")
        }
        
        return (false, nil)
    }
    
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
