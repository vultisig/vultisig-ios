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

    static func getPreSignedInputData(
        keysignPayload: KeysignPayload, vault: Vault
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

        guard AnyAddress(string: keysignPayload.toAddress, coin: .xrp) != nil
        else {
            throw HelperError.runtimeError("fail to get to address")
        }

        let publicKey = try CoinFactory.publicKey(
            asset: keysignPayload.coin.toCoinMeta(), vault: vault)

        let operation = RippleOperationPayment.with {

            if let memo = keysignPayload.memo {
                $0.destinationTag = UInt64(memo) ?? 0
            }

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

    static func getPreSignedImageHash(
        keysignPayload: KeysignPayload, vault: Vault
    ) throws -> [String] {
        let inputData = try getPreSignedInputData(
            keysignPayload: keysignPayload, vault: vault)

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
        vaultHexPubKey: String,
        keysignPayload: KeysignPayload,
        signatures: [String: TssKeysignResponse],
        vault: Vault
    ) throws -> SignedTransactionResult {

        let publicKey = try CoinFactory.publicKey(
            asset: keysignPayload.coin.toCoinMeta(), vault: vault)

        let inputData = try getPreSignedInputData(
            keysignPayload: keysignPayload, vault: vault)
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
