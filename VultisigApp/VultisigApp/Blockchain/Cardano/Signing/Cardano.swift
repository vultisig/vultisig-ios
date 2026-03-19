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
 ✅ Send Max 5 ADA, Balance 5 ADA → WalletCore subtracts fee automatically (valid)
 */

class CardanoHelper {

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
    /// - Send Max 5 ADA, Balance 5 ADA → WalletCore subtracts fee automatically ✅ (valid)
    ///
    /// - Parameters:
    ///   - sendAmount: Amount to send in lovelaces
    ///   - totalBalance: Total available balance in lovelaces  
    ///   - estimatedFee: Estimated transaction fee in lovelaces
    ///   - sendMaxAmount: Whether this is a MAX send (skips fee validation like UTXO chains)
    /// - Returns: Tuple with validation result and error message if any
    static func validateUTXORequirements(sendAmount: BigInt, totalBalance: BigInt, estimatedFee: BigInt, sendMaxAmount: Bool = false) -> (isValid: Bool, errorMessage: String?) {
        let minUTXOValue = defaultMinUTXOValue

        // For MAX sends, only validate that we have enough balance to cover fees
        // The wallet will automatically deduct fees from the total, just like UTXO chains
        if sendMaxAmount {
            if totalBalance <= estimatedFee {
                let availableADA = totalBalance.toADAString
                return (false, "Insufficient balance (\(availableADA) ADA). Balance must be greater than transaction fees.")
            }
            return (true, nil)
        }

        // Regular validation for non-MAX sends
        // 1. Check send amount meets minimum
        if sendAmount < minUTXOValue {
            let minAmountADA = minUTXOValue.toADAString
            return (false, "Minimum send amount is \(minAmountADA) ADA. Cardano requires this to prevent spam.")
        }

        // 2. Check sufficient balance
        let totalNeeded = sendAmount + estimatedFee
        if totalBalance < totalNeeded {
            // For MAX amount display, truncate to 5 decimal places to match getMaxValue behavior
            let totalBalanceDecimal = totalBalance.toADA
            let truncatedBalance = totalBalanceDecimal.truncated(toPlaces: 5) // ADA has 6 decimals, so decimals - 1 = 5
            let totalBalanceADA = truncatedBalance.formatToDecimal(digits: 5)

            // Recommend Send Max for insufficient balance
            if totalBalance > estimatedFee && totalBalance > 0 {
                return (false, "Insufficient balance. 💡 Try 'Send Max' to send \(totalBalanceADA) ADA instead.")
            } else {
                let availableADA = totalBalance.toADAString
                return (false, "Insufficient balance (\(availableADA) ADA). You need more ADA to complete this transaction.")
            }
        }

        // 3. Check remaining balance (change) meets minimum UTXO requirement
        let remainingBalance = totalBalance - sendAmount - estimatedFee
        if remainingBalance > 0 && remainingBalance < minUTXOValue {
            // For MAX amount display, truncate to 5 decimal places to match getMaxValue behavior
            let totalBalanceDecimal = totalBalance.toADA
            let truncatedBalance = totalBalanceDecimal.truncated(toPlaces: 5) // ADA has 6 decimals, so decimals - 1 = 5
            let totalBalanceADA = truncatedBalance.formatToDecimal(digits: 5)

            // Always recommend Send Max for change issues - simplest solution
            return (false, "This amount would leave too little change. 💡 Try 'Send Max' (\(totalBalanceADA) ADA) to avoid this issue.")
        }

        return (true, nil)
    }

    /// Check if balance is low and should recommend "Send Max" to avoid UTXO issues
    /// - Parameters:
    ///   - totalBalance: Total available balance in lovelaces
    ///   - estimatedFee: Estimated transaction fee in lovelaces
    /// - Returns: Tuple indicating if balance is low and recommendation message
    static func shouldRecommendSendMax(totalBalance: BigInt, estimatedFee: BigInt) -> (shouldRecommend: Bool, message: String?) {

        // Balance is considered "low" if total balance is less than 3.5 ADA
        // This helps avoid change issues with the 1.4 ADA minimum
        let lowBalanceThreshold: BigInt = 3_500_000 // 3.5 ADA in lovelaces

        if totalBalance <= lowBalanceThreshold && totalBalance > estimatedFee {
            // For MAX amount display, truncate to 5 decimal places to match getMaxValue behavior
            let totalBalanceDecimal = totalBalance.toADA
            let truncatedBalance = totalBalanceDecimal.truncated(toPlaces: 5) // ADA has 6 decimals, so decimals - 1 = 5
            let totalBalanceADA = truncatedBalance.formatToDecimal(digits: 5)

            return (true, "💡 Low balance detected. Consider 'Send Max' (\(totalBalanceADA) ADA) to avoid change issues.")
        }

        return (false, nil)
    }

    /// Calculate dynamic transaction fee using WalletCore's transaction planning
    /// Similar to how UTXO chains calculate fees dynamically
    func getCardanoTransactionPlan(keysignPayload: KeysignPayload) throws -> CardanoTransactionPlan {
        // Reuse existing getPreSignedInputData and deserialize it
        let inputData = try CardanoHelper.getPreSignedInputData(keysignPayload: keysignPayload)
        let input = try CardanoSigningInput(serializedBytes: inputData)
        let plan: CardanoTransactionPlan = AnySigner.plan(input: input, coin: .cardano)

        // Check for transaction plan errors
        if plan.error != .ok {
            throw HelperError.runtimeError("Cardano transaction plan error: \(plan.error)")
        }

        return plan
    }

    /// Calculate dynamic fee for Cardano transaction using WalletCore planning
    /// This replaces the fixed fee approach with actual transaction size calculation
    func calculateDynamicFee(keysignPayload: KeysignPayload) throws -> BigInt {
        let plan = try getCardanoTransactionPlan(keysignPayload: keysignPayload)
        return BigInt(plan.fee)
    }

    // MARK: - Helper Functions

    static func getPreSignedInputData(keysignPayload: KeysignPayload) throws -> Data {
        guard keysignPayload.coin.chain == .cardano else {
            throw HelperError.runtimeError("coin is not ADA")
        }

        guard case .Cardano(_, let sendMaxAmount, let ttl) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("fail to get Cardano chain specific parameters")
        }

        guard AnyAddress(string: keysignPayload.toAddress, coin: .cardano) != nil else {
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

        // Calculate transaction hash manually since WalletCore output.txID is empty for Cardano
        let transactionHash = calculateCardanoTransactionHash(from: output.encoded)

        let result = SignedTransactionResult(rawTransaction: output.encoded.hexString,
                                           transactionHash: transactionHash)
        return result
    }

    /// Calculate Cardano Transaction ID manually following official specification
    /// Cardano TX ID = Blake2b-256 hash of the transaction BODY only (not complete transaction)
    /// Transaction CBOR structure: [body, witness_set, valid_script?, metadata?]
    static func calculateCardanoTransactionHash(from transactionData: Data) -> String {

        do {
            // Parse CBOR to extract transaction body (first element)
            let transactionBodyData = try extractCardanoTransactionBody(from: transactionData)

            // Cardano Transaction ID = Blake2b-256 hash (32 bytes) of the BODY only
            let txidHash = Hash.blake2b(data: transactionBodyData, size: 32)
            let finalHash = txidHash.hexString

            return finalHash
        } catch {
            print("❌ Error parsing Cardano CBOR: \(error)")

            // Fallback: try using the complete transaction (this might be wrong but better than crashing)
            let txidHash = Hash.blake2b(data: transactionData, size: 32)
            let fallbackHash = txidHash.hexString

            print("⚠️ Fallback TX ID from COMPLETE transaction: \(fallbackHash)")
            return fallbackHash
        }
    }

    /// Extract transaction body from Cardano CBOR structure
    /// Cardano transaction CBOR format: [body, witness_set, valid_script?, metadata?]
    /// We need only the first element (body) for TX ID calculation
    private static func extractCardanoTransactionBody(from transactionData: Data) throws -> Data {
        // Convert Data to bytes for CBOR parsing
        let bytes = [UInt8](transactionData)

        // Parse CBOR manually to extract the first element (transaction body)
        // Cardano transaction is a CBOR array: [body, witnesses, ...]

        var index = 0

        // Parse CBOR array header
        guard index < bytes.count else {
            throw HelperError.runtimeError("Invalid CBOR: empty data")
        }

        let firstByte = bytes[index]
        index += 1

        // Check if it's a CBOR array (major type 4)
        let majorType = (firstByte >> 5) & 0x07
        guard majorType == 4 else {
            throw HelperError.runtimeError("Invalid CBOR: expected array, got major type \(majorType)")
        }

        // Get array length
        let arrayInfo = firstByte & 0x1F
        var arrayLength: Int

        if arrayInfo < 24 {
            arrayLength = Int(arrayInfo)
        } else if arrayInfo == 24 {
            guard index < bytes.count else {
                throw HelperError.runtimeError("Invalid CBOR: array length truncated")
            }
            arrayLength = Int(bytes[index])
            index += 1
        } else {
            throw HelperError.runtimeError("Unsupported CBOR array length encoding")
        }

        guard arrayLength >= 2 else {
            throw HelperError.runtimeError("Invalid Cardano transaction: array too short")
        }

        // Find the start and end of the first element (transaction body)
        let bodyStartIndex = index
        let bodyEndIndex = try findEndOfCBORItem(bytes: bytes, startIndex: bodyStartIndex)

        // Extract the body bytes
        let bodyBytes = Array(bytes[bodyStartIndex..<bodyEndIndex])
        return Data(bodyBytes)
    }

    /// Helper function to find the end of a CBOR item
    private static func findEndOfCBORItem(bytes: [UInt8], startIndex: Int) throws -> Int {
        var index = startIndex

        guard index < bytes.count else {
            throw HelperError.runtimeError("CBOR parsing: index out of bounds")
        }

        let firstByte = bytes[index]
        index += 1

        let majorType = (firstByte >> 5) & 0x07
        let additionalInfo = firstByte & 0x1F

        // Handle different CBOR types
        switch majorType {
        case 0, 1: // Unsigned integer, Negative integer
            if additionalInfo < 24 {
                return index
            } else if additionalInfo == 24 {
                return index + 1
            } else if additionalInfo == 25 {
                return index + 2
            } else if additionalInfo == 26 {
                return index + 4
            } else if additionalInfo == 27 {
                return index + 8
            }

        case 2, 3: // Byte string, Text string
            let length = try readCBORLength(bytes: bytes, index: &index, additionalInfo: additionalInfo)
            return index + length

        case 4: // Array
            let arrayLength = try readCBORLength(bytes: bytes, index: &index, additionalInfo: additionalInfo)
            for _ in 0..<arrayLength {
                index = try findEndOfCBORItem(bytes: bytes, startIndex: index)
            }
            return index

        case 5: // Map
            let mapLength = try readCBORLength(bytes: bytes, index: &index, additionalInfo: additionalInfo)
            for _ in 0..<(mapLength * 2) { // key-value pairs
                index = try findEndOfCBORItem(bytes: bytes, startIndex: index)
            }
            return index

        case 7: // Float, Simple value
            if additionalInfo < 20 {
                return index
            } else if additionalInfo == 20 || additionalInfo == 21 {
                return index
            } else if additionalInfo == 22 {
                return index + 1
            } else if additionalInfo == 25 {
                return index + 2
            } else if additionalInfo == 26 {
                return index + 4
            } else if additionalInfo == 27 {
                return index + 8
            }

        default:
            throw HelperError.runtimeError("Unsupported CBOR major type: \(majorType)")
        }

        throw HelperError.runtimeError("CBOR parsing failed")
    }

    /// Helper function to read CBOR length values
    private static func readCBORLength(bytes: [UInt8], index: inout Int, additionalInfo: UInt8) throws -> Int {
        if additionalInfo < 24 {
            return Int(additionalInfo)
        } else if additionalInfo == 24 {
            guard index < bytes.count else {
                throw HelperError.runtimeError("CBOR length truncated")
            }
            let length = Int(bytes[index])
            index += 1
            return length
        } else if additionalInfo == 25 {
            guard index + 1 < bytes.count else {
                throw HelperError.runtimeError("CBOR length truncated")
            }
            let length = Int(bytes[index]) << 8 | Int(bytes[index + 1])
            index += 2
            return length
        } else if additionalInfo == 26 {
            guard index + 3 < bytes.count else {
                throw HelperError.runtimeError("CBOR length truncated")
            }
            let length = Int(bytes[index]) << 24 | Int(bytes[index + 1]) << 16 | Int(bytes[index + 2]) << 8 | Int(bytes[index + 3])
            index += 4
            return length
        } else {
            throw HelperError.runtimeError("Unsupported CBOR length encoding")
        }
    }
}

// MARK: - BigInt Extension for ADA Formatting
extension BigInt {
    /// Safely convert lovelaces to ADA using Decimal for precision
    var toADA: Decimal {
        return Decimal(string: self.description)! / 1_000_000
    }

    /// Format as ADA string with appropriate decimal places
    var toADAString: String {
        let decimal = self.toADA
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 6
        formatter.numberStyle = .decimal
        return formatter.string(from: decimal as NSDecimalNumber) ?? "0"
    }
}
