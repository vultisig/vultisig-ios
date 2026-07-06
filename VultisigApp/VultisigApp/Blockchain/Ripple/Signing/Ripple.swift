//
//  Ton.Swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 20/10/24.
//

import BigInt
import Foundation
import OSLog
import Tss
import WalletCore

private let logger = Logger(subsystem: "com.vultisig.app", category: "ripple-helper")

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
            case .Ripple(let sequence, let gas, let lastLedgerSequence, let fieldDestinationTag) = keysignPayload
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

        let destinationTag: UInt64?
        if keysignPayload.swapPayload != nil {
            // Swap payloads keep the legacy memo behavior byte-for-byte so
            // mixed-version committees stay in agreement:
            // - SwapKit XRP stringifies the resolved destination tag into the
            //   memo slot → numeric memo becomes a wallet-core destinationTag;
            // - THORChain swaps carry the protocol's text routing memo, which
            //   must ride the on-chain `Memos` field for THORChain to read.
            if let memoValue = keysignPayload.memo, !memoValue.isEmpty {
                guard let numericTag = UInt64(memoValue) else {
                    return try swapMemoSigningInput(
                        keysignPayload: keysignPayload,
                        memoValue: memoValue,
                        gas: gas,
                        sequence: sequence,
                        lastLedgerSequence: lastLedgerSequence,
                        publicKey: publicKey
                    )
                }
                destinationTag = numericTag
            } else {
                destinationTag = nil
            }
        } else if let fieldDestinationTag {
            // Dual-write rollout: prefer the first-class RippleSpecific
            // `destination_tag`. The initiator writes the same value into both
            // this field and the memo carrier, so a co-signer that reads only
            // the memo rebuilds an identical signing input — the pre-image hash
            // matches across mixed-version device pairs. When the field is
            // present it wins outright (the memo is not re-validated): a
            // divergent memo can at worst fail the ceremony on a legacy peer,
            // never produce a signature.
            //
            // A present tag of 0 is rejected exactly as the memo path rejects
            // "0": wallet-core serialises a 0 destinationTag identically to
            // "no tag", so signing it would produce an UNTAGGED payment while a
            // tag was displayed — the dishonest-signing shape the contract
            // forbids. (No wallet-core signer can produce a tagged-0 payment on
            // any platform, so a 0 field is always malformed.)
            guard fieldDestinationTag != 0 else {
                throw RippleMemoError.invalidMemo(String(fieldDestinationTag))
            }
            destinationTag = UInt64(fieldDestinationTag)
        } else {
            // Plain payments with no field: the memo slot is the destination-tag
            // carrier — it must be empty or a canonical uint32 decimal, and
            // anything else rejects the payload on both sides of the ceremony
            // (see `RippleDestinationTag`). This replaces the legacy fallback
            // that turned non-numeric memos into an on-chain `Memos` blob, which
            // silently dropped the tag and left exchange deposits uncredited.
            destinationTag = try RippleDestinationTag.validatePayloadMemo(keysignPayload.memo).map(UInt64.init)
        }

        let operation = RippleOperationPayment.with {
            $0.destination = keysignPayload.toAddress
            $0.amount = Int64(keysignPayload.toAmount.description) ?? 0
            if let destinationTag {
                $0.destinationTag = destinationTag
            }
        }

        let input = RippleSigningInput.with {
            $0.fee = Int64(gas)
            $0.sequence = UInt32(sequence)  // from account info api
            $0.account = keysignPayload.coin.address
            $0.publicKey = publicKey.data
            $0.opPayment = operation
            $0.lastLedgerSequence = UInt32(lastLedgerSequence)
        }

        logger.info("Creating XRP payment, destinationTag: \(destinationTag.map(String.init) ?? "none", privacy: .public), lastLedgerSequence: \(lastLedgerSequence)")

        return try input.serializedData()
    }

    /// Legacy raw-JSON signing input carrying the memo as an on-chain XRPL
    /// `Memos` entry. Reachable only for swap payloads — THORChain-family
    /// swaps route via a text memo the protocol reads on-chain. Plain sends
    /// never take this path anymore: a text memo there was the fund-loss
    /// shape (tag typo → Memos blob → uncredited exchange deposit).
    private static func swapMemoSigningInput(
        keysignPayload: KeysignPayload,
        memoValue: String,
        gas: UInt64,
        sequence: UInt64,
        lastLedgerSequence: UInt64,
        publicKey: PublicKey
    ) throws -> Data {
        let txJson: [String: Any] = [
            "TransactionType": "Payment",
            "Account": keysignPayload.coin.address,
            "Destination": keysignPayload.toAddress,
            "Amount": String(keysignPayload.toAmount.description),
            "Fee": String(gas),
            "Sequence": sequence,
            "LastLedgerSequence": lastLedgerSequence,
            "Memos": [
                [
                    "Memo": [
                        "MemoData": memoValue.data(using: .utf8)?.map { String(format: "%02hhx", $0) }.joined() ?? ""
                    ]
                ]
            ]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: txJson, options: [])
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw HelperError.runtimeError("Failed to create JSON string")
        }

        let input = RippleSigningInput.with {
            $0.fee = Int64(gas)
            $0.sequence = UInt32(sequence)
            $0.account = keysignPayload.coin.address
            $0.publicKey = publicKey.data
            $0.lastLedgerSequence = UInt32(lastLedgerSequence)
            $0.rawJson = jsonString
        }

        logger.info("Creating XRP swap transaction with text memo, lastLedgerSequence: \(lastLedgerSequence)")

        return try input.serializedData()
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
