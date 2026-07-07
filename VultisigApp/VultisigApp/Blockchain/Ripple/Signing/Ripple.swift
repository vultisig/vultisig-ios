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
                    return try memoSigningInput(
                        keysignPayload: keysignPayload,
                        memoValue: memoValue,
                        destinationTag: nil,
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
            // Plain payment WITH a first-class tag field. The initiator
            // dual-writes the tag into the field and populates the memo slot per
            // the send it built (empty / echoed tag / real text). Resolve the
            // pair deterministically so every device — new field-reader and old
            // memo-only co-signer alike — either agrees on the bytes or fails
            // the ceremony (never signs the wrong tx):
            //
            // - A present tag of 0 is rejected exactly as memo "0" is:
            //   wallet-core serialises a 0 destinationTag identically to "no
            //   tag", so signing it would send UNTAGGED while a tag was
            //   displayed — the dishonest-signing shape the contract forbids.
            guard fieldDestinationTag != 0 else {
                throw RippleMemoError.invalidMemo(String(fieldDestinationTag))
            }

            if let memoValue = keysignPayload.memo, !memoValue.isEmpty {
                if memoValue == String(fieldDestinationTag) {
                    // Dual-write ECHO: the memo carries the tag's own canonical
                    // decimal. Build a plain tag-only payment (NO Memos) — this
                    // is byte-identical to the tag-only path an old memo-only
                    // co-signer produces, keeping the committee in agreement.
                    destinationTag = UInt64(fieldDestinationTag)
                } else if RippleDestinationTag.parseCanonical(memoValue) != nil {
                    // A DIFFERENT canonical number can't ride alongside the tag
                    // (the memo slot would read as a second, conflicting tag on
                    // a legacy peer). Reject deterministically.
                    throw RippleMemoError.tagMemoConflict(tag: fieldDestinationTag, memo: memoValue)
                } else {
                    // COMBO: a genuine text memo alongside the tag. XRPL carries
                    // both as independent fields; wallet-core's typed payment has
                    // no memo slot, so build a rawJson Payment with BOTH the
                    // DestinationTag and a Memos blob. (An OLD co-signer with no
                    // field reads only the text memo → builds a Memos-only tx
                    // without the tag → hash diverges → the ceremony fails safe.
                    // Accepted mixed-version limitation.)
                    return try memoSigningInput(
                        keysignPayload: keysignPayload,
                        memoValue: memoValue,
                        destinationTag: fieldDestinationTag,
                        gas: gas,
                        sequence: sequence,
                        lastLedgerSequence: lastLedgerSequence,
                        publicKey: publicKey
                    )
                }
            } else {
                // Tag-only (empty memo).
                destinationTag = UInt64(fieldDestinationTag)
            }
        } else if let memoValue = keysignPayload.memo, !memoValue.isEmpty {
            // Plain payment, NO field — the memo slot is the source of truth
            // (what every legacy platform reads):
            if RippleDestinationTag.parseCanonical(memoValue) != nil {
                // Numeric-canonical → the legacy "type the tag into the memo"
                // tag carrier. Unchanged from before: a canonical nonzero value
                // becomes the destinationTag; "0" is rejected.
                destinationTag = try RippleDestinationTag.validatePayloadMemo(memoValue).map(UInt64.init)
            } else {
                // Genuine text → an on-chain `Memos` blob. This RESTORES the
                // pre-#4749 memo-only capability (memo-only sends are
                // byte-identical old-vs-new: no field on the wire, same text in
                // the memo slot).
                return try memoSigningInput(
                    keysignPayload: keysignPayload,
                    memoValue: memoValue,
                    destinationTag: nil,
                    gas: gas,
                    sequence: sequence,
                    lastLedgerSequence: lastLedgerSequence,
                    publicKey: publicKey
                )
            }
        } else {
            // No field, no memo → plain untagged payment.
            destinationTag = nil
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

    /// Raw-JSON signing input carrying a text memo as an on-chain XRPL `Memos`
    /// entry, optionally alongside a native `DestinationTag`. wallet-core's
    /// typed `RippleOperationPayment` has no memo field, so any transaction that
    /// must carry an on-chain memo has to go through rawJson.
    ///
    /// Two callers:
    /// - **swaps** (`destinationTag == nil`) — THORChain-family swaps route via
    ///   a text memo the protocol reads on-chain. This branch is byte-identical
    ///   to the legacy `swapMemoSigningInput` (same key set), so swap signing is
    ///   unchanged.
    /// - **plain tag + memo combo** (`destinationTag != nil`) — a plain XRP send
    ///   carrying BOTH a destination tag and a text memo (XRPL allows both as
    ///   independent fields). Adds a numeric `DestinationTag` next to the Memos
    ///   blob.
    private static func memoSigningInput(
        keysignPayload: KeysignPayload,
        memoValue: String,
        destinationTag: UInt32?,
        gas: UInt64,
        sequence: UInt64,
        lastLedgerSequence: UInt64,
        publicKey: PublicKey
    ) throws -> Data {
        var txJson: [String: Any] = [
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
        // Only inserted for the combo path, so the swap dict keeps the exact key
        // set (and therefore byte-identical serialization) it has always had.
        // XRPL `DestinationTag` is a numeric field — emit a JSON number.
        if let destinationTag {
            txJson["DestinationTag"] = destinationTag
        }

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

        logger.info("Creating XRP rawJson payment (memo\(destinationTag != nil ? " + tag" : "", privacy: .public)), lastLedgerSequence: \(lastLedgerSequence)")

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
