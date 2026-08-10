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
import VultisigCommonData
import WalletCore

private let logger = Log.chain.other

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
            case .Ripple(
                let sequence,
                let gas,
                let lastLedgerSequence,
                let fieldDestinationTag,
                let fieldTransactionType
            ) = keysignPayload.chainSpecific
        else {
            logger.error("keysignPayload.chainSpecific is not Ripple")
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

        // Issued-currency (trust-line token) operations. Both sit AFTER the
        // dApp branch — a rawJson transaction is always signed verbatim — and
        // BEFORE the `toAddress` guard, because a TrustSet has no destination at
        // all, exactly like the dApp offer case that already skips it.
        //
        // The precedence is deliberate and load-bearing for MPC byte-parity:
        //   1. `signRipple`                      → verbatim rawJson
        //   2. `transaction_type == trustSet`    → opTrustSet (amount = LIMIT)
        //   3. non-native coin with a token id   → opPayment.currencyAmount
        //   4. native XRP                        → opPayment.amount (drops)
        //
        // (2) before (3) is what makes a mixed-version TrustSet ceremony work: a
        // co-signer predating `transaction_type` sees only "non-native Ripple
        // coin" and builds a TrustSet from the same limit, which is byte-identical
        // to what this branch produces.
        //
        // ⚠️ The converse is NOT symmetric, and it is a deliberate trade rather
        // than an oversight. Because an absent discriminator is indistinguishable
        // from `.unspecified`, arm (3) claims the "non-native, no discriminator"
        // case that every shipped signer today reads as a TrustSet. That is the
        // only way an issued-currency Payment can be expressed at all — inferring
        // TrustSet from the coin alone is precisely why sending XRPL tokens has
        // been impossible. The consequences, in full:
        //   - a token send whose committee includes a signer predating the field
        //     DIVERGES → the ceremony fails and no funds move (fail-safe);
        //   - a TrustSet ORIGINATED by a signer predating the field would be read
        //     here as a token Payment. No shipped client can originate one (no
        //     platform builds XRPL token payloads at all yet — this app is the
        //     first), so the case is unreachable today; it stops being reachable
        //     for good once every platform sets the field.
        // Both are stated in the PR body rather than left to be rediscovered.
        switch fieldTransactionType {
        case VSTransactionType.unspecified.rawValue:
            break
        case VSTransactionType.rippleTrustSet.rawValue:
            return try trustSetSigningInput(
                keysignPayload: keysignPayload,
                gas: gas,
                sequence: sequence,
                lastLedgerSequence: lastLedgerSequence
            )
        default:
            // A discriminator this build doesn't recognise — another chain's
            // operation relayed onto a Ripple payload, or a future XRPL
            // operation. Refuse: the peer is describing something other than
            // what these branches would build, so signing anything at all would
            // be signing an operation nobody reviewed.
            throw HelperError.runtimeError(
                "XRP payload carries an unsupported transaction type (\(fieldTransactionType))"
            )
        }

        // Classify the coin ONCE, before any operation is built, so an
        // ill-formed coin can never slip into the wrong encoding further down.
        let coinKind = try issuedCurrencyKind(coin: keysignPayload.coin)

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

        // An issued-currency Payment encodes its amount as a `CurrencyAmount`
        // (currency / issuer / decimal value string), never as drops. Branch
        // AFTER the tag resolution above so the tag rides a token Payment
        // exactly as it rides a native one — the tag is orthogonal to how the
        // amount is encoded.
        if coinKind == .issuedCurrency {
            return try tokenPaymentSigningInput(
                keysignPayload: keysignPayload,
                destinationTag: destinationTag,
                gas: gas,
                sequence: sequence,
                lastLedgerSequence: lastLedgerSequence,
                publicKey: publicKey
            )
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

    // MARK: - Issued currency (trust-line tokens)

    /// Which amount encoding a coin is entitled to on the XRPL signing path.
    private enum RippleCoinKind {
        /// Native XRP: the amount is drops.
        case native
        /// A trust-line token: the amount is a `CurrencyAmount` triple.
        case issuedCurrency
    }

    /// Classifies the payload's coin, refusing anything structurally
    /// inconsistent.
    ///
    /// The whole `Coin` arrives proto-relayed from a peer, and `isNativeToken`
    /// and `contractAddress` between them decide which AMOUNT ENCODING gets
    /// signed — so the two must agree before either is trusted. Both
    /// contradictions are refused rather than interpreted:
    ///
    /// - **non-native with NO token id** satisfies no issued-currency branch, so
    ///   it would fall through to the native encoding and have its token base
    ///   units serialized as XRP DROPS — a silent token→native crossing that
    ///   moves real XRP;
    /// - **native WITH a token id** is the mirror image: metadata that names an
    ///   issuer while asking to be signed as drops. Nothing legitimate produces
    ///   it (`Coin.contractAddress` is empty for native XRP everywhere in the
    ///   app), and a payload that cannot describe its own asset coherently is
    ///   not one to sign.
    ///
    /// Deeper metadata (ticker, decimals) is NOT policed here: those vary
    /// legitimately across platforms, and rejecting on them would false-reject
    /// valid payloads from a peer rather than catch an attack.
    private static func issuedCurrencyKind(coin: Coin) throws -> RippleCoinKind {
        if coin.isNativeToken {
            guard coin.contractAddress.isEmpty else {
                throw HelperError.runtimeError(
                    "XRP coin claims to be native but carries an issued-currency token id"
                )
            }
            return .native
        }
        guard !coin.contractAddress.isEmpty else {
            throw HelperError.runtimeError(
                "XRP non-native coin is missing its issued-currency token id"
            )
        }
        return .issuedCurrency
    }

    /// Signing input for a `TrustSet`: open or modify the trust line that lets
    /// this account hold an issuer's currency.
    ///
    /// **The keysign `toAmount` IS the trust line's limit**, not a transfer — the
    /// maximum of that currency this account is willing to hold. That identity is
    /// the SDK resolver's convention (`getTrustSet`), and preserving it is what
    /// makes a mixed-version ceremony work: a co-signer predating
    /// `RippleSpecific.transaction_type` infers "TrustSet" from a non-native
    /// Ripple coin and formats the very same amount as the limit, producing
    /// byte-identical bytes. Do not "improve" it into a separate limit field
    /// without changing the wire contract on every platform first.
    ///
    /// A TrustSet has no destination and no `Amount`, so this runs before the
    /// `toAddress` guard — like the dApp offer case.
    ///
    /// `SigningInput.flags` is deliberately left unset. WalletCore stamps
    /// `tfFullyCanonicalSig` on typed operations and the SDK sets no flags;
    /// writing `tfSetNoRipple` here would risk clobbering that default and break
    /// byte-parity with every other signer.
    private static func trustSetSigningInput(
        keysignPayload: KeysignPayload,
        gas: UInt64,
        sequence: UInt64,
        lastLedgerSequence: UInt64
    ) throws -> Data {
        let coin = keysignPayload.coin
        // A TrustSet is meaningless for native XRP: there is no issuer to trust.
        // Fail closed rather than emitting a SigningInput whose limitAmount
        // names an empty currency and issuer.
        guard try issuedCurrencyKind(coin: coin) == .issuedCurrency else {
            throw HelperError.runtimeError("XRP TrustSet requires an issued-currency coin carrying a token id")
        }

        let limitAmount = try issuedCurrencyAmount(
            coin: coin,
            amount: keysignPayload.toAmount,
            role: "TrustSet limit"
        )
        let envelope = try signingEnvelope(
            keysignPayload: keysignPayload,
            gas: gas,
            sequence: sequence,
            lastLedgerSequence: lastLedgerSequence
        )

        let input = RippleSigningInput.with {
            $0.fee = envelope.fee
            $0.sequence = envelope.sequence
            $0.account = coin.address
            $0.publicKey = envelope.publicKey.data
            $0.lastLedgerSequence = envelope.lastLedgerSequence
            $0.opTrustSet = RippleOperationTrustSet.with { $0.limitAmount = limitAmount }
        }

        logger.info("Creating XRP TrustSet, lastLedgerSequence: \(lastLedgerSequence)")

        return try input.serializedData()
    }

    /// Signing input for an issued-currency `Payment`: transfer a trust-line
    /// token to `toAddress`.
    ///
    /// Uses `opPayment.currencyAmount` — the `oneof` alternative to the drops
    /// `amount` — so the value rides as a decimal string against the coin's
    /// (currency, issuer) pair. `destinationTag` is whatever the shared
    /// tag/memo resolution already decided; the tag is an independent XRPL field
    /// and applies to a token Payment exactly as it does to a native one.
    ///
    /// There is no old-signer counterpart for this operation (every signer
    /// predating `transaction_type` reads a non-native coin as a TrustSet), so a
    /// mixed-version committee diverges here and the ceremony fails without
    /// moving funds — fail-safe, and stated plainly rather than papered over.
    private static func tokenPaymentSigningInput(
        keysignPayload: KeysignPayload,
        destinationTag: UInt64?,
        gas: UInt64,
        sequence: UInt64,
        lastLedgerSequence: UInt64,
        publicKey: PublicKey
    ) throws -> Data {
        let currencyAmount = try issuedCurrencyAmount(
            coin: keysignPayload.coin,
            amount: keysignPayload.toAmount,
            role: "Payment amount"
        )

        let operation = RippleOperationPayment.with {
            $0.destination = keysignPayload.toAddress
            // Setting `currencyAmount` selects the oneof arm, so the drops
            // `amount` is not on the wire at all — a token Payment must never
            // carry a drops amount.
            $0.currencyAmount = currencyAmount
            if let destinationTag {
                $0.destinationTag = destinationTag
            }
        }

        let envelope = try signingEnvelope(
            keysignPayload: keysignPayload,
            gas: gas,
            sequence: sequence,
            lastLedgerSequence: lastLedgerSequence
        )

        let input = RippleSigningInput.with {
            $0.fee = envelope.fee
            $0.sequence = envelope.sequence
            $0.account = keysignPayload.coin.address
            $0.publicKey = publicKey.data
            $0.opPayment = operation
            $0.lastLedgerSequence = envelope.lastLedgerSequence
        }

        logger.info(
            "Creating XRP issued-currency payment, destinationTag: \(destinationTag.map(String.init) ?? "none", privacy: .public), lastLedgerSequence: \(lastLedgerSequence)"
        )

        return try input.serializedData()
    }

    /// Builds the WalletCore `CurrencyAmount` for `coin`'s token id at `amount`
    /// base units.
    ///
    /// Every `RippleIssuedCurrency` helper throws rather than trapping precisely
    /// so a hostile token id or `decimals` becomes a REJECTED transaction instead
    /// of a crashed signer. `role` names which field failed so the surfaced error
    /// says what the signer refused to build.
    private static func issuedCurrencyAmount(
        coin: Coin,
        amount: BigInt,
        role: String
    ) throws -> RippleCurrencyAmount {
        let token: (currency: String, issuer: String)
        do {
            token = try RippleIssuedCurrency.parseRippleTokenId(coin.contractAddress)
        } catch {
            throw HelperError.runtimeError("XRP \(role): malformed token id '\(coin.contractAddress)'")
        }

        let currencyCode: String
        do {
            currencyCode = try RippleIssuedCurrency.toXrplCurrencyCode(token.currency)
        } catch {
            throw HelperError.runtimeError("XRP \(role): invalid currency code '\(token.currency)'")
        }

        // The coin's currency is only trustworthy if WalletCore will put it on
        // the wire unchanged. It uppercases a 3-BYTE code before encoding, and
        // XRPL codes are case-sensitive, so a lowercase standard code would sign
        // a DIFFERENT currency than the one reviewed. A coin can reach here from
        // trust-line discovery or a restored vault, not only from the add-token
        // field, so the refusal belongs at this boundary rather than only at the
        // one that happens to be validated.
        guard RippleIssuedCurrency.isSignableCurrencyCode(currencyCode) else {
            throw HelperError.runtimeError(
                "XRP \(role): currency code '\(currencyCode)' cannot be signed verbatim"
            )
        }

        let value: String
        do {
            value = try RippleIssuedCurrency.formatIssuedCurrencyValue(
                amount: amount,
                decimals: coin.decimals
            )
        } catch {
            throw HelperError.runtimeError("XRP \(role): value is not representable at \(coin.decimals) decimals")
        }

        return RippleCurrencyAmount.with {
            $0.currency = currencyCode
            $0.issuer = token.issuer
            $0.value = value
        }
    }

    /// Envelope fields shared by every typed XRPL operation.
    ///
    /// The proto-relayed fee / sequence / ledger sequence are narrowed with
    /// `exactly:` so a hostile out-of-range value throws (fail closed) instead of
    /// trapping the signer — the convention `dappSigningInput` established. Real
    /// XRPL values always fit, so this is byte-identical to the unchecked
    /// conversions for every legitimate payload.
    private static func signingEnvelope(
        keysignPayload: KeysignPayload,
        gas: UInt64,
        sequence: UInt64,
        lastLedgerSequence: UInt64
    ) throws -> (fee: Int64, sequence: UInt32, lastLedgerSequence: UInt32, publicKey: PublicKey) {
        guard let publicKeyData = Data(hexString: keysignPayload.coin.hexPublicKey) else {
            throw HelperError.runtimeError("invalid hex public key")
        }
        guard let publicKey = PublicKey(data: publicKeyData, type: .secp256k1) else {
            throw HelperError.runtimeError("invalid public key data")
        }
        guard let fee = Int64(exactly: gas) else {
            throw HelperError.runtimeError("XRP fee is out of range")
        }
        guard let sequence32 = UInt32(exactly: sequence) else {
            throw HelperError.runtimeError("XRP sequence is out of range")
        }
        guard let lastLedgerSequence32 = UInt32(exactly: lastLedgerSequence) else {
            throw HelperError.runtimeError("XRP lastLedgerSequence is out of range")
        }
        return (fee, sequence32, lastLedgerSequence32, publicKey)
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
    /// 3. A `Payment` must not set `tfPartialPayment` without a delivery floor,
    ///    since that flag turns the just-bound `Amount` back into a ceiling.
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

        // Before ANY check reads the decoded object: refuse a rawJson whose two
        // readers would not agree on what it says. See the function's docs — the
        // two parsers resolve a duplicate key to DIFFERENT values, so every check
        // below could otherwise be passed by one value and signed with another.
        try assertNoDuplicateJsonKeys(in: rawJson)

        // Fail closed: the transaction must spend from the signing vault.
        guard tx["Account"] as? String == keysignPayload.coin.address else {
            throw HelperError.runtimeError("signRipple rawJson Account does not match the signing account")
        }

        // Applies to EVERY transaction type, before any type-specific binding.
        //
        // wallet-core uppercases a 3-byte currency code before encoding — measured
        // on this exact rawJson path, not inferred from the typed one — so a code
        // it would alter must be refused wherever it appears. Gating only
        // `Payment.Amount` left TrustSet's `LimitAmount` and OfferCreate's
        // `TakerGets`/`TakerPays` free to be reviewed as `usd` and signed as
        // `USD`: a different trust line, or a DEX offer against a different pair,
        // than the one shown to the co-signer. `Payment.SendMax` / `DeliverMin`
        // had the same gap.
        try assertEveryCurrencyCodeIsSignable(in: tx)

        // Payments are additionally expressible by the payload metadata, so bind
        // them to the reviewed destination and amount, then refuse the flags
        // that would quietly unbind that amount again. Other types (offers /
        // trust lines / escrows) are not reconstructable from toAddress/toAmount
        // and pass on the Account and currency-code checks alone.
        if tx["TransactionType"] as? String == "Payment" {
            try bindPaymentToReviewedValues(tx: tx, keysignPayload: keysignPayload)
            try assertPaymentDeliveryIsBounded(tx: tx)
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

    /// Refuses a rawJson that repeats a key inside one JSON object.
    ///
    /// Duplicate keys are syntactically legal JSON and RFC 8259 leaves the winner
    /// unspecified, so every parser picks its own. The two parsers standing
    /// either side of this gate pick DIFFERENT ones — measured on this exact
    /// path, not assumed: `JSONSerialization` keeps the FIRST occurrence and
    /// wallet-core's parser keeps the LAST.
    ///
    /// Every check in `dappSigningInput` reads the object `JSONSerialization`
    /// produced, while wallet-core signs the same text through its own parser. So
    /// a dApp that writes a key twice gets its first value reviewed and its
    /// second value signed — `{"Destination":"<reviewed>",…,"Destination":"<theirs>"}`
    /// binds against the address the co-signer approved and pays the other one.
    /// That is the exact mismatch class the rest of this file exists to close.
    ///
    /// The collapsed object cannot say what wallet-core will keep, so the text is
    /// scanned and any repeat is refused outright. Nothing legitimate is lost: a
    /// duplicate key expresses nothing a single-keyed object cannot, and a
    /// transaction that means two different things to its two readers is not one
    /// a co-signer can review.
    ///
    /// Keys are compared DECODED, so `"a"` and `"a"` count as the same key —
    /// which is how both parsers compare them.
    private static func assertNoDuplicateJsonKeys(in rawJson: String) throws {
        let duplicate = HelperError.runtimeError(
            "signRipple rawJson repeats a JSON key, which the signer and this reviewer resolve differently"
        )

        let scalars = Array(rawJson.unicodeScalars)
        // Two parallel stacks rather than one stack of enum payloads, so a key
        // set is mutated IN PLACE through its subscript. Rebuilding the set per
        // key would copy every key seen so far on each insertion — quadratic in
        // an object's field count, and the field count is dApp-controlled.
        var containerIsObject: [Bool] = []
        var objectKeys: [Set<String>] = []
        var lastStringLiteral: String?
        var index = 0

        while index < scalars.count {
            switch scalars[index] {
            case "{":
                containerIsObject.append(true)
                objectKeys.append([])
                lastStringLiteral = nil
                index += 1
            case "[":
                containerIsObject.append(false)
                lastStringLiteral = nil
                index += 1
            case "}", "]":
                if let wasObject = containerIsObject.popLast(), wasObject {
                    objectKeys.removeLast()
                }
                lastStringLiteral = nil
                index += 1
            case "\"":
                // Consuming the whole literal is also what keeps a `:` or a brace
                // INSIDE a string value from being read as structure.
                guard let string = readJsonStringLiteral(scalars, from: index) else {
                    throw duplicate
                }
                lastStringLiteral = string.literal
                index = string.next
            case ":":
                // A `:` at object level always follows that object's key. The
                // input already parsed as JSON, so anything else here is
                // unreachable — refuse rather than guess.
                guard containerIsObject.last == true,
                      let literal = lastStringLiteral,
                      let key = decodedJsonString(literal) else {
                    throw duplicate
                }
                guard objectKeys[objectKeys.count - 1].insert(key).inserted else {
                    throw duplicate
                }
                lastStringLiteral = nil
                index += 1
            default:
                index += 1
            }
        }
    }

    /// Consumes the JSON string starting at `start` (the opening quote) and
    /// returns the literal WITH its quotes plus the index just past the closing
    /// quote. `nil` when the string never terminates.
    private static func readJsonStringLiteral(
        _ scalars: [Unicode.Scalar],
        from start: Int
    ) -> (literal: String, next: Int)? {
        var literal = String.UnicodeScalarView()
        literal.append("\"")
        var index = start + 1

        while index < scalars.count {
            let scalar = scalars[index]
            literal.append(scalar)
            index += 1
            if scalar == "\\" {
                // The escaped scalar cannot end the string, whatever it is.
                guard index < scalars.count else { return nil }
                literal.append(scalars[index])
                index += 1
                continue
            }
            if scalar == "\"" {
                return (String(literal), index)
            }
        }
        return nil
    }

    /// Decoded value of a JSON string literal (quotes included), so two spellings
    /// of one key compare equal. Escapes are resolved by the same decoder that
    /// produced the object every other check reads.
    private static func decodedJsonString(_ literal: String) -> String? {
        guard literal.contains("\\") else {
            return String(literal.dropFirst().dropLast())
        }
        guard let data = "[\(literal)]".data(using: .utf8),
              let decoded = try? JSONSerialization.jsonObject(with: data) as? [String],
              decoded.count == 1 else {
            return nil
        }
        return decoded[0]
    }

    /// Refuses the signature if any issued-currency code anywhere in the
    /// transaction would not survive encoding verbatim.
    ///
    /// Walks the whole decoded object rather than a fixed field list, so a field
    /// this signer does not know about — a future transaction type, or a nested
    /// term — is covered by default instead of silently exempt.
    ///
    /// The verdict is taken on the RAW string, never on a normalised one. The
    /// rawJson reaches the signer byte for byte, so any normalisation applied
    /// here that the signer does not apply is a place where this walk's verdict
    /// and the signed bytes can disagree — and `toXrplCurrencyCode` normalises
    /// by trimming whitespace and ASCII-packing, neither of which the signer
    /// does. See ``RippleIssuedCurrency/isVerbatimSignableCurrencyCode(_:)``.
    private static func assertEveryCurrencyCodeIsSignable(in value: Any) throws {
        let mangled = HelperError.runtimeError(
            "signRipple rawJson currency code would be altered by the signer"
        )

        if let object = value as? [String: Any] {
            if let currency = object["currency"] as? String {
                guard RippleIssuedCurrency.isVerbatimSignableCurrencyCode(currency) else {
                    throw mangled
                }
            }
            for nested in object.values {
                try assertEveryCurrencyCodeIsSignable(in: nested)
            }
        } else if let array = value as? [Any] {
            for element in array {
                try assertEveryCurrencyCodeIsSignable(in: element)
            }
        }
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
                // The rawJson is handed to WalletCore VERBATIM, and it uppercases
                // a 3-BYTE currency code before encoding. A code it would mangle
                // must be refused even when both sides spell it the same way:
                // agreeing on `usd` still puts `USD` on the ledger, which is a
                // currency neither the dApp nor the reviewer named. Judged on the
                // RAW string for the same reason the walk above is — normalising
                // first is exactly what let a whitespace-edged 3-byte code
                // through. Redundant today (the walk already ran over this
                // object), kept so this binding does not depend on that ordering.
                guard RippleIssuedCurrency.isVerbatimSignableCurrencyCode(iouCurrency) else {
                    throw amountMismatch
                }
                let normalizedIou = try RippleIssuedCurrency.toXrplCurrencyCode(iouCurrency)
                let currencyMatches = try normalizedIou
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

    /// Refuses a dApp `Payment` whose reviewed `Amount` no longer bounds what
    /// the recipient actually gets.
    ///
    /// The binding `bindPaymentToReviewedValues` just established only means
    /// something while `Amount` is a delivery. `tfPartialPayment` turns it into
    /// a ceiling: the ledger hands over whatever the chosen path can source and
    /// records the real figure only in the executed transaction's metadata
    /// (`delivered_amount`). The reviewed `toAmount` still matches byte for
    /// byte, still describes nothing the recipient will receive, and the sender
    /// can be charged the full `SendMax`. The cross-currency self-swap —
    /// `Destination` is the sender's own address — turns an attractive receive
    /// figure into dust for the price of the whole `SendMax`.
    ///
    /// A well-formed, strictly positive `DeliverMin` restores a floor, so a
    /// partial payment carrying one is forwarded unchanged; they are
    /// legitimate. Without one there is nothing left binding the outcome, so
    /// refuse rather than sign terms no reviewer could have seen. `Flags` that
    /// cannot be read as a uint32 are refused for the same reason: they may
    /// carry the very bit being checked.
    ///
    /// Scoped to `Payment` deliberately — `0x00020000` is namespace-sensitive.
    /// It is `tfImmediateOrCancel` on an `OfferCreate`, and as an account-root
    /// flag it is `lsfRequireDestTag`; reading it as partial payment anywhere
    /// else would be wrong.
    ///
    /// `Paths` is NOT refused. It is legitimate on a cross-currency payment and
    /// refusing it would break real DEX flows; the review screen surfaces it
    /// instead, which is where a routing choice belongs.
    private static func assertPaymentDeliveryIsBounded(tx: [String: Any]) throws {
        // Read from the SAME decoded object every other check reads, so the
        // duplicate-key guard that already ran covers this field too.
        guard let flags = RippleDAppTransaction.parseFlags(tx["Flags"]) else {
            throw HelperError.runtimeError("signRipple rawJson Flags is not a uint32 bitmask")
        }
        guard flags & RippleDAppTransaction.tfPartialPayment != 0 else { return }

        guard isPositiveXrplAmount(tx["DeliverMin"]) else {
            throw HelperError.runtimeError(
                "signRipple rawJson sets tfPartialPayment without a usable DeliverMin floor"
            )
        }
    }

    /// Upper bound on the length of a drops string before it reaches `BigInt`.
    /// XRPL's maximum is 10^17 drops (18 digits); 20 characters covers that
    /// plus a sign and slack, while a pathologically long string is refused
    /// before it can burn CPU on its way to being rejected anyway.
    private static let maxDropsStringLength = 20

    /// Whether a value is a well-formed, strictly positive XRPL amount — a
    /// drops string or an issued-currency object.
    ///
    /// A `DeliverMin` only floors a delivery if it is one. `null`, `{}`, `"0"`
    /// and `{"value":"0",…}` all satisfy "the field is present" while bounding
    /// nothing, so presence alone cannot stand in for a floor.
    ///
    /// An issued value below the smallest representable unit truncates to zero
    /// through `parseIssuedCurrencyValue` and is refused on the same grounds: a
    /// floor under the resolution of the ledger amount is not a floor.
    private static func isPositiveXrplAmount(_ value: Any?) -> Bool {
        if let drops = value as? String {
            guard drops.count <= maxDropsStringLength, let parsed = BigInt(drops) else {
                return false
            }
            return parsed > 0
        }
        if let iou = value as? [String: Any] {
            guard iou["currency"] is String,
                  iou["issuer"] is String,
                  let iouValue = iou["value"] as? String,
                  let parsed = try? RippleIssuedCurrency.parseIssuedCurrencyValue(iouValue) else {
                return false
            }
            return parsed > 0
        }
        return false
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
        // FAIL CLOSED: this rawJson encodes `Amount` as a DROPS string, which is
        // only correct for native XRP. ANY non-native coin reaching here would be
        // signed as a native XRP transfer of the token's base units — a real,
        // silent loss of funds — so the check is on `isNativeToken` alone, not on
        // whether a token id happens to be present. WalletCore's typed payment
        // has no memo slot and a token rawJson Payment is not part of the wire
        // contract yet, so refuse rather than guess.
        guard keysignPayload.coin.isNativeToken else {
            throw HelperError.runtimeError("XRP issued-currency payments cannot carry an on-chain memo")
        }

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
            logger.error("\(preSigningOutput.errorMessage, privacy: .public)")
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
            logger.error("\(preSigningOutput.errorMessage, privacy: .public)")
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
            logger.error("\(errorMessage, privacy: .public)")
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
            logger.error("errorMessage: \(errorMessage, privacy: .public)")
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
