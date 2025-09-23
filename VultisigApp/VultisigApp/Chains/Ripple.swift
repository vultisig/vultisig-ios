//
//  Ton.Swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 20/10/24.
//

import BigInt
import Foundation
import Tss
import WalletCore

enum RippleHelper {
    
    /*
     https://xrpl.org/docs/concepts/accounts/reserves
     Ripple deletes your account if less than 1 XRP
     */
    static let defaultExistentialDeposit: BigInt = pow(10, 6).description.toBigInt() // 1 XRP
    
    static func getSwapPreSignedInputData(keysignPayload: KeysignPayload) throws -> Data {
        // For XRP swaps, we use the same logic as regular transactions but with swap memo
        return try getPreSignedInputData(keysignPayload: keysignPayload)
    }
    
    static func getPreSignedInputData(keysignPayload: KeysignPayload
    ) throws -> Data {
        
        guard keysignPayload.coin.chain == Chain.ripple else {
            throw HelperError.runtimeError("coin is not XRP")
        }
        
        guard
            case .Ripple(let sequence, let gas, let lastLedgerSequence) = keysignPayload
                .chainSpecific
        else {
            print("keysignPayload.chainSpecific is not Ripple")
            throw HelperError.runtimeError(
                "getPreSignedInputData: fail to get account number and sequence"
            )
        }
        
        guard AnyAddress(string: keysignPayload.toAddress, coin: .xrp) != nil else {
            throw HelperError.runtimeError("fail to get to address")
        }
        guard let publicKeyData = Data(hexString: keysignPayload.coin.hexPublicKey) else {
            throw HelperError.runtimeError("invalid hex public key")
        }
        guard let publicKey = PublicKey(data: publicKeyData, type: .secp256k1) else {
            throw HelperError.runtimeError("invalid public key data")
        }

        // Check if we need to include a memo or destinationTag in the transaction
        if let memoValue = keysignPayload.memo, !memoValue.isEmpty {
            // Check if the memo is an integer (for destinationTag) or a string (for memo data)
            if let destinationTag = UInt64(memoValue) {
                // If it's an integer, use it as destinationTag with the standard operation
                let operation = RippleOperationPayment.with {
                    $0.destination = keysignPayload.toAddress
                    $0.amount = Int64(keysignPayload.toAmount.description) ?? 0
                    $0.destinationTag = destinationTag
                }
                
                let input = RippleSigningInput.with {
                    $0.fee = Int64(gas)
                    $0.sequence = UInt32(sequence)  // from account info api
                    $0.account = keysignPayload.coin.address
                    $0.publicKey = publicKey.data
                    $0.opPayment = operation
                    $0.lastLedgerSequence = UInt32(lastLedgerSequence)
                }
                
                print("Creating XRP transaction with destinationTag: \(destinationTag)")
                print("UInt32(lastLedgerSequence) \(UInt32(lastLedgerSequence))")
                
                return try input.serializedData()
            } else {
                // Memo text not supported by current WalletCore binary: proceed without memo
                let operation = RippleOperationPayment.with {
                    $0.destination = keysignPayload.toAddress
                    $0.amount = Int64(keysignPayload.toAmount.description) ?? 0
                }
                let input = RippleSigningInput.with {
                    $0.fee = Int64(gas)
                    $0.sequence = UInt32(sequence)
                    $0.account = keysignPayload.coin.address
                    $0.publicKey = publicKey.data
                    $0.opPayment = operation
                    $0.lastLedgerSequence = UInt32(lastLedgerSequence)
                }
                return try input.serializedData()
            }
        } else {
            // Standard transaction without memo
            let operation = RippleOperationPayment.with {
                $0.destination = keysignPayload.toAddress
                $0.amount = Int64(keysignPayload.toAmount.description) ?? 0
            }
            
            let input = RippleSigningInput.with {
                $0.fee = Int64(gas)
                $0.sequence = UInt32(sequence)  // from account info api
                $0.account = keysignPayload.coin.address
                $0.publicKey = publicKey.data
                $0.opPayment = operation
                $0.lastLedgerSequence = UInt32(lastLedgerSequence)
            }
            
            print("UInt32(lastLedgerSequence) \(UInt32(lastLedgerSequence))")
            
            return try input.serializedData()
        }
    }
    
    static func getPreSignedImageHash(keysignPayload: KeysignPayload) throws -> [String] {
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)
        
        let hashes = TransactionCompiler.preImageHashes(
            coinType: .xrp, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(
            serializedBytes: hashes)
        if !preSigningOutput.errorMessage.isEmpty {
            print(preSigningOutput.errorMessage)
            throw HelperError.runtimeError(preSigningOutput.errorMessage)
        }
        return [preSigningOutput.dataHash.hexString]
    }
    
    static func getSignedTransaction(
        keysignPayload: KeysignPayload,
        signatures: [String: TssKeysignResponse]) throws -> SignedTransactionResult {
        
        guard let publicKeyData = Data(hexString: keysignPayload.coin.hexPublicKey) else {
            throw HelperError.runtimeError("invalid hex public key")
        }
            guard let publicKey = PublicKey(data: publicKeyData, type: .secp256k1) else {
            throw HelperError.runtimeError("invalid public key data")
        }
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)
        let hashes = TransactionCompiler.preImageHashes(
            coinType: .xrp, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(
            serializedBytes: hashes)
        
        if !preSigningOutput.errorMessage.isEmpty {
            print(preSigningOutput.errorMessage)
            throw HelperError.runtimeError(preSigningOutput.errorMessage)
        }
        
        let allSignatures = DataVector()
        let publicKeys = DataVector()
        
        let signatureProvider = SignatureProvider(signatures: signatures)
        
        // If I use datahash it is not finding anything
        let signature = signatureProvider.getSignatureWithRecoveryID(
            preHash: preSigningOutput.dataHash)
        guard
            publicKey.verify(
                signature: signature, message: preSigningOutput.dataHash)
        else {
            let errorMessage = "Invalid signature"
            print("\(errorMessage)")
            throw HelperError.runtimeError(errorMessage)
        }
        
        allSignatures.add(data: signature)
            publicKeys.add(data: publicKey.data)
        let compileWithSignature = TransactionCompiler.compileWithSignatures(
            coinType: .xrp,
            txInputData: inputData,
            signatures: allSignatures,
            publicKeys: publicKeys)
        
        let output = try RippleSigningOutput(
            serializedBytes: compileWithSignature)
        
        // The error is HERE it accepted it as a DER previously
        if !output.errorMessage.isEmpty {
            let errorMessage = output.errorMessage
            print("errorMessage: \(errorMessage)")
            throw HelperError.runtimeError(errorMessage)
        }
        
        let result = SignedTransactionResult(
            rawTransaction: output.encoded.hexString,
            transactionHash: "")
        
        return result
    }
    
}
