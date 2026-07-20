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

        // dApp-supplied XRPL transactions (OfferCreate / cross-currency Payment
        // / OfferCancel / TrustSet) arrive as raw JSON in `signRipple`.
        // WalletCore signs that JSON verbatim through its Ripple `rawJson` path
        // (the same path the text-memo case below uses), so every co-signer
        // rebuilds an identical signing input and produces byte-identical bytes
        // — we never reconstruct an `opPayment` from `toAddress` / `toAmount`.
        // Offers carry an empty `toAddress`, so this branch sits BEFORE the
        // `toAddress` guard. Fails closed before signing (see
        // `dappSigningInput`) so a co-signer never signs a tx that spends an
        // account other than its own vault, nor a Payment whose destination /
        // amount drifts from the reviewed values.
        if let signRipple = keysignPayload.signRipple {
            return try dappSigningInput(
                keysignPayload: keysignPayload,
                rawJson: signRipple.rawJson,
                gas: gas,
                sequence: sequence,
                lastLedgerSequence: lastLedgerSequence
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

    /// Builds the signing input for a dApp-supplied XRPL transaction carried
    /// verbatim in `signRipple.rawJson`, and fails closed before signing.
    ///
    /// Ports the SDK resolver (`core/mpc/keysign/signingInputs/resolvers/
    /// ripple.ts`): the raw JSON is signed as-is (WalletCore canonicalizes it,
    /// so byte-parity with the extension/SDK follows from the identical
    /// envelope + JSON), but only after two defence-in-depth checks so a
    /// co-signer never blind-signs someone else's transaction:
    /// 1. `Account` must equal this vault's derived XRP address.
    /// 2. A `Payment` (the only type expressible by the reviewed
    ///    `toAddress`/`toAmount`) must bind its `Destination` to `toAddress`
    ///    and its `Amount` to `toAmount` — native drops or, for an
    ///    issued-currency object, currency + issuer + value against the
    ///    reviewed coin's token id. Offers, escrows and trust lines pass on the
    ///    `Account` check alone (they carry no reviewed toAddress/toAmount).
    private static func dappSigningInput(
        keysignPayload: KeysignPayload,
        rawJson: String,
        gas: UInt64,
        sequence: UInt64,
        lastLedgerSequence: UInt64
    ) throws -> Data {
        guard !rawJson.isEmpty else {
            throw HelperError.runtimeError("signRipple keysign payload is missing rawJson")
        }
        guard let jsonData = rawJson.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: jsonData) else {
            throw HelperError.runtimeError("signRipple rawJson is not valid JSON")
        }
        guard let tx = parsed as? [String: Any] else {
            throw HelperError.runtimeError("signRipple rawJson is not a transaction object")
        }

        // Fail closed: the transaction must spend from the signing vault.
        guard tx["Account"] as? String == keysignPayload.coin.address else {
            throw HelperError.runtimeError("signRipple rawJson Account does not match the signing account")
        }

        // Payments are expressible by the payload metadata, so bind them to the
        // reviewed destination and amount. Other types (offers / trust lines /
        // escrows) are not reconstructable from toAddress/toAmount and pass on
        // the Account check alone.
        if tx["TransactionType"] as? String == "Payment" {
            try bindPaymentToReviewedValues(tx: tx, keysignPayload: keysignPayload)
        }

        guard let publicKeyData = Data(hexString: keysignPayload.coin.hexPublicKey) else {
            throw HelperError.runtimeError("invalid hex public key")
        }
        guard let publicKey = PublicKey(data: publicKeyData, type: .secp256k1) else {
            throw HelperError.runtimeError("invalid public key data")
        }

        // Narrow the proto-relayed envelope values with `exactly:` so a hostile
        // out-of-range fee / sequence / ledger sequence throws (fail closed)
        // rather than trapping the signer. Real XRPL values always fit.
        guard let fee = Int64(exactly: gas) else {
            throw HelperError.runtimeError("signRipple fee is out of range")
        }
        guard let sequence32 = UInt32(exactly: sequence) else {
            throw HelperError.runtimeError("signRipple sequence is out of range")
        }
        guard let lastLedgerSequence32 = UInt32(exactly: lastLedgerSequence) else {
            throw HelperError.runtimeError("signRipple lastLedgerSequence is out of range")
        }

        let input = RippleSigningInput.with {
            $0.fee = fee
            $0.sequence = sequence32
            $0.account = keysignPayload.coin.address
            $0.publicKey = publicKey.data
            $0.lastLedgerSequence = lastLedgerSequence32
            $0.rawJson = rawJson
        }

        logger.info("Creating XRP dApp rawJson transaction, lastLedgerSequence: \(lastLedgerSequence)")

        return try input.serializedData()
    }

    /// Fail-closed binding for a dApp `Payment`: `Destination` must equal the
    /// reviewed `toAddress`, and `Amount` must equal the reviewed `toAmount`
    /// (native drops string, or an issued-currency object matched to the coin's
    /// Ripple token id). Any parse failure in the issued-currency helpers is
    /// caught and surfaced as an amount mismatch — the signer rejects, never
    /// crashes. Mirrors the SDK `getRawJson` Payment branch.
    private static func bindPaymentToReviewedValues(
        tx: [String: Any],
        keysignPayload: KeysignPayload
    ) throws {
        guard tx["Destination"] as? String == keysignPayload.toAddress else {
            throw HelperError.runtimeError("signRipple rawJson Destination does not match the reviewed toAddress")
        }

        let amountMismatch = HelperError.runtimeError("signRipple rawJson Amount does not match the reviewed toAmount")
        let coin = keysignPayload.coin

        if let dropsString = tx["Amount"] as? String {
            // Native XRP: Amount is a drops string.
            guard coin.isNativeToken, dropsString == keysignPayload.toAmount.description else {
                throw amountMismatch
            }
        } else if let iou = tx["Amount"] as? [String: Any] {
            // Issued currency: bind currency + issuer + numeric value to the
            // reviewed coin's Ripple token id ("<currencyCode>.<issuer>").
            guard !coin.isNativeToken, !coin.contractAddress.isEmpty else {
                throw amountMismatch
            }
            do {
                let token = try RippleIssuedCurrency.parseRippleTokenId(coin.contractAddress)
                guard let iouCurrency = iou["currency"] as? String,
                      let iouIssuer = iou["issuer"] as? String,
                      let iouValue = iou["value"] as? String else {
                    throw amountMismatch
                }
                let currencyMatches = try RippleIssuedCurrency.toXrplCurrencyCode(iouCurrency)
                    == RippleIssuedCurrency.toXrplCurrencyCode(token.currency)
                let issuerMatches = iouIssuer == token.issuer
                let reviewedValue = try RippleIssuedCurrency.parseIssuedCurrencyValue(
                    RippleIssuedCurrency.formatIssuedCurrencyValue(
                        amount: keysignPayload.toAmount,
                        decimals: coin.decimals
                    )
                )
                let valueMatches = try RippleIssuedCurrency.parseIssuedCurrencyValue(iouValue) == reviewedValue
                guard currencyMatches, issuerMatches, valueMatches else {
                    throw amountMismatch
                }
            } catch let error as HelperError {
                throw error
            } catch {
                // Any parse failure (bad token id, currency code too long,
                // malformed value / exponent) is a mismatch, not a crash.
                throw amountMismatch
            }
        } else {
            // Missing or unrepresentable Amount.
            throw amountMismatch
        }
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
            transactionHash: signedTransactionHash(signedBlob: output.encoded))

        return result
    }

    /// XRPL "transaction identifying hash": SHA-512Half (the first 32 bytes of
    /// SHA-512) over the 4-byte `TXN\0` prefix (`HashPrefix::transactionID`,
    /// `0x54584E00`) concatenated with the serialized *signed* transaction blob.
    /// Rendered as uppercase hex — the canonical XRPL rendering, and the same
    /// value the `submit`/`tx` endpoints echo back as `tx_json.hash`.
    ///
    /// Derived purely from the already-signed output bytes; no signing input,
    /// pre-image, or TSS state is involved.
    ///
    /// An empty blob yields an empty string so the hash-keyed keysign safety
    /// nets stay disarmed rather than keying off a meaningless prefix-only hash.
    ///
    /// Reference: https://xrpl.org/docs/references/protocol/data-types/hash-prefixes
    static func signedTransactionHash(signedBlob: Data) -> String {
        guard !signedBlob.isEmpty else { return "" }
        let transactionIDPrefix = Data([0x54, 0x58, 0x4E, 0x00]) // "TXN\0"
        let digest = Data(Hash.sha512(data: transactionIDPrefix + signedBlob).prefix(32))
        return digest.toHexString().uppercased()
    }

}
