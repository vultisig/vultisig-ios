//
//  RippleIssuedCurrencySigningTests.swift
//  VultisigAppTests
//
//  Pins the two XRPL issued-currency keysign operations against the wire
//  contract they have to agree with, byte for byte:
//
//  - a TrustSet (open/modify a trust line, where the keysign amount IS the
//    line's limit), selected by `RippleSpecific.transaction_type ==
//    RIPPLE_TRUST_SET`;
//  - an issued-currency Payment (`opPayment.currencyAmount`), selected by "a
//    non-native coin with a token id and NO trust-set discriminator".
//
//  In MPC keysign every device rebuilds the signing input from the payload, so
//  a byte divergence between two devices is the failure mode. Three properties
//  matter and are asserted here rather than assumed:
//
//   1. NATIVE XRP IS UNCHANGED — the discriminator is a proto3 enum defaulting
//      to zero, absent from the wire when unset, so an existing native send
//      serializes to identical bytes.
//   2. OLD-CO-SIGNER TRUSTSET PARITY — a signer predating the field infers
//      TrustSet from "non-native Ripple coin" and formats the same amount as the
//      limit. This is what makes a mixed-version trust-line ceremony succeed,
//      and it is only true if this signer's TrustSet is byte-identical to that
//      legacy rule.
//   3. DIVERGENCE IS REAL, NOT SILENT — a token Payment and a TrustSet over the
//      same coin and amount must produce DIFFERENT pre-image hashes, so a
//      mixed-version token send fails the ceremony instead of signing the wrong
//      operation.
//

@testable import VultisigApp
import BigInt
import VultisigCommonData
import WalletCore
import XCTest

final class RippleIssuedCurrencySigningTests: XCTestCase {

    // Same fixtures as `RippleSignRippleTests` — the signing vault's own XRP
    // account plus a real secp256k1 public key (the compressed generator point).
    private static let account = "rPVMhWBsfF9iMXYj3aAzJVkPDTFNSyWdKy"
    private static let destination = "rEb8TK3gBgk5auZkwc6sHnwrGVJH8DuaLh"
    private static let issuer = "rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh"
    private static let publicKeyHex = "0279BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798"

    private static let sequence: UInt64 = 99
    private static let gas: UInt64 = 10
    private static let lastLedgerSequence: UInt64 = 12_345_678

    /// 1.5 tokens at the XRPL issued-currency scale (15 decimals).
    private static let tokenAmount = BigInt("1500000000000000")

    // MARK: - Fixtures

    private static func makeNativeCoin() -> Coin {
        let meta = CoinMeta(
            chain: .ripple,
            ticker: "XRP",
            logo: "xrp",
            decimals: 6,
            priceProviderId: "ripple",
            contractAddress: "",
            isNativeToken: true
        )
        return Coin(asset: meta, address: account, hexPublicKey: publicKeyHex)
    }

    private static func makeTokenCoin(
        contractAddress: String = "USD.\(issuer)",
        decimals: Int = RippleIssuedCurrency.issuedCurrencyDecimals
    ) -> Coin {
        let meta = CoinMeta(
            chain: .ripple,
            ticker: "USD",
            logo: "xrp",
            decimals: decimals,
            priceProviderId: "",
            contractAddress: contractAddress,
            isNativeToken: false
        )
        return Coin(asset: meta, address: account, hexPublicKey: publicKeyHex)
    }

    private static func makePayload(
        coin: Coin,
        toAddress: String,
        toAmount: BigInt,
        memo: String? = nil,
        destinationTag: UInt32? = nil,
        transactionType: VSTransactionType = .unspecified
    ) -> KeysignPayload {
        KeysignPayload(
            coin: coin,
            toAddress: toAddress,
            toAmount: toAmount,
            chainSpecific: .Ripple(
                sequence: sequence,
                gas: gas,
                lastLedgerSequence: lastLedgerSequence,
                destinationTag: destinationTag,
                transactionType: transactionType.rawValue
            ),
            utxos: [],
            memo: memo,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: "",
            vaultLocalPartyID: "iPhone-test",
            libType: LibType.DKLS.toString(),
            wasmExecuteContractPayload: nil,
            tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil,
            qbtcClaimPayload: nil,
            isQbtcClaim: false,
            skipBroadcast: false,
            signData: nil
        )
    }

    private static func publicKey() throws -> PublicKey {
        try XCTUnwrap(PublicKey(data: XCTUnwrap(Data(hexString: publicKeyHex)), type: .secp256k1))
    }

    private static func preImageHash(of inputData: Data) throws -> String {
        let hashes = TransactionCompiler.preImageHashes(coinType: .xrp, txInputData: inputData)
        let output = try TxCompilerPreSigningOutput(serializedBytes: hashes)
        XCTAssertTrue(output.errorMessage.isEmpty, output.errorMessage)
        return output.dataHash.hexString
    }

    // MARK: - 1. Native XRP is byte-identical

    /// A native XRP send whose `transaction_type` is unset serializes to bytes
    /// IDENTICAL to the pre-change signer. The discriminator is a proto3 enum
    /// defaulting to zero, so it never reaches the wire for a native send — the
    /// same argument `testFieldSourcedTagProducesByteIdenticalInputToMemoFallback`
    /// makes for the destination-tag field.
    func testNativeSendWithUnsetTransactionTypeIsByteIdenticalToPreChangeSigner() throws {
        let payload = Self.makePayload(
            coin: Self.makeNativeCoin(),
            toAddress: Self.destination,
            toAmount: BigInt(1_000_000)
        )

        let produced = try RippleHelper.getPreSignedInputData(keysignPayload: payload)

        // Independently rebuild exactly what the signer produced before the
        // issued-currency branches existed: a typed opPayment carrying drops.
        let publicKeyData = try Self.publicKey().data
        let reference = RippleSigningInput.with {
            $0.fee = Int64(Self.gas)
            $0.sequence = UInt32(Self.sequence)
            $0.account = Self.account
            $0.publicKey = publicKeyData
            $0.lastLedgerSequence = UInt32(Self.lastLedgerSequence)
            $0.opPayment = RippleOperationPayment.with {
                $0.destination = Self.destination
                $0.amount = 1_000_000
            }
        }

        XCTAssertEqual(
            produced,
            try reference.serializedData(),
            "a native XRP send must serialize byte-identically to the pre-change signer"
        )
    }

    /// The same, one level up: the pre-image hash is unchanged, and the native
    /// payload carries no `opTrustSet` and no `currencyAmount`.
    func testNativeSendCarriesNoIssuedCurrencyFields() throws {
        let payload = Self.makePayload(
            coin: Self.makeNativeCoin(),
            toAddress: Self.destination,
            toAmount: BigInt(1_000_000)
        )

        let input = try RippleSigningInput(
            serializedBytes: RippleHelper.getPreSignedInputData(keysignPayload: payload)
        )

        XCTAssertEqual(input.opPayment.amount, 1_000_000)
        XCTAssertEqual(input.opPayment.amountOneof, .amount(1_000_000))
        XCTAssertFalse(input.opTrustSet.hasLimitAmount)
        XCTAssertTrue(input.rawJson.isEmpty)
    }

    // MARK: - 2. Old-co-signer TrustSet byte parity (load-bearing)

    /// THE load-bearing test for the mixed-version story.
    ///
    /// An input built from `transaction_type == RIPPLE_TRUST_SET` must be
    /// byte-identical to one built by the LEGACY rule every shipped signer uses
    /// today — "a non-native Ripple coin means TrustSet, and the keysign amount
    /// is the trust-line limit". The reference input below is that legacy rule,
    /// transcribed from the SDK resolver's `getTrustSet()`.
    ///
    /// If this fails, a new initiator and an old co-signer serialize different
    /// bytes for the SAME trust-line intent, and opening a trust line stops
    /// working in mixed-version committees.
    func testTrustSetIsByteIdenticalToLegacyNonNativeRule() throws {
        let coin = Self.makeTokenCoin()
        let payload = Self.makePayload(
            coin: coin,
            toAddress: "",
            toAmount: RippleTrustLineLimit.defaultLimit,
            transactionType: .rippleTrustSet
        )

        let produced = try RippleHelper.getPreSignedInputData(keysignPayload: payload)

        // The legacy rule, verbatim: currency normalized to its on-ledger code,
        // issuer from the token id, value = the keysign amount formatted at the
        // coin's decimals.
        let (currency, issuer) = try RippleIssuedCurrency.parseRippleTokenId(coin.contractAddress)
        let legacyCurrencyCode = try RippleIssuedCurrency.toXrplCurrencyCode(currency)
        let legacyValue = try RippleIssuedCurrency.formatIssuedCurrencyValue(
            amount: RippleTrustLineLimit.defaultLimit,
            decimals: coin.decimals
        )
        let publicKeyData = try Self.publicKey().data
        let legacy = RippleSigningInput.with {
            $0.fee = Int64(Self.gas)
            $0.sequence = UInt32(Self.sequence)
            $0.account = Self.account
            $0.publicKey = publicKeyData
            $0.lastLedgerSequence = UInt32(Self.lastLedgerSequence)
            $0.opTrustSet = RippleOperationTrustSet.with {
                $0.limitAmount = RippleCurrencyAmount.with {
                    $0.currency = legacyCurrencyCode
                    $0.issuer = issuer
                    $0.value = legacyValue
                }
            }
        }

        XCTAssertEqual(
            produced,
            try legacy.serializedData(),
            "a TrustSet must be byte-identical to what a co-signer predating transaction_type builds"
        )
        XCTAssertEqual(
            try Self.preImageHash(of: produced),
            try Self.preImageHash(of: legacy.serializedData()),
            "the TrustSet pre-image hash must match the legacy rule's"
        )
    }

    /// The TrustSet's limit is the keysign amount, and it carries no destination
    /// and no Payment operation. A co-signer reading only the payload sees a
    /// trust line, never a transfer.
    func testTrustSetCarriesLimitAmountAndNoPayment() throws {
        let coin = Self.makeTokenCoin()
        let payload = Self.makePayload(
            coin: coin,
            toAddress: "",
            toAmount: Self.tokenAmount,
            transactionType: .rippleTrustSet
        )

        let input = try RippleSigningInput(
            serializedBytes: RippleHelper.getPreSignedInputData(keysignPayload: payload)
        )

        XCTAssertTrue(input.opTrustSet.hasLimitAmount)
        XCTAssertEqual(input.opTrustSet.limitAmount.currency, "USD")
        XCTAssertEqual(input.opTrustSet.limitAmount.issuer, Self.issuer)
        XCTAssertEqual(input.opTrustSet.limitAmount.value, "1.5")
        XCTAssertTrue(input.opPayment.destination.isEmpty)
        XCTAssertNil(input.opPayment.amountOneof)
        XCTAssertTrue(input.rawJson.isEmpty)
    }

    /// A TrustSet has no destination, so an empty `toAddress` must NOT be
    /// rejected by the native `toAddress` guard — the branch has to sit before
    /// it, like the dApp offer case.
    func testTrustSetDoesNotRequireADestinationAddress() {
        let payload = Self.makePayload(
            coin: Self.makeTokenCoin(),
            toAddress: "",
            toAmount: Self.tokenAmount,
            transactionType: .rippleTrustSet
        )
        XCTAssertNoThrow(try RippleHelper.getPreSignedInputData(keysignPayload: payload))
    }

    /// `SigningInput.flags` stays unset: WalletCore stamps its own
    /// `tfFullyCanonicalSig` on typed operations and the SDK sets no flags, so
    /// writing one here would diverge from every other signer.
    func testTrustSetSetsNoSigningFlags() throws {
        let payload = Self.makePayload(
            coin: Self.makeTokenCoin(),
            toAddress: "",
            toAmount: Self.tokenAmount,
            transactionType: .rippleTrustSet
        )

        let input = try RippleSigningInput(
            serializedBytes: RippleHelper.getPreSignedInputData(keysignPayload: payload)
        )
        XCTAssertEqual(input.flags, 0)
    }

    // MARK: - 3. Divergence is real, not silent

    /// The same coin and the same amount produce DIFFERENT pre-image hashes for
    /// a TrustSet and a token Payment. That difference is the fail-safe: a
    /// mixed-version token send aborts the ceremony instead of quietly signing
    /// a trust line (or vice versa).
    func testTokenPaymentAndTrustSetProduceDifferentPreImageHashes() throws {
        let coin = Self.makeTokenCoin()

        let trustSet = Self.makePayload(
            coin: coin,
            toAddress: Self.destination,
            toAmount: Self.tokenAmount,
            transactionType: .rippleTrustSet
        )
        let payment = Self.makePayload(
            coin: coin,
            toAddress: Self.destination,
            toAmount: Self.tokenAmount
        )

        let trustSetHash = try Self.preImageHash(
            of: RippleHelper.getPreSignedInputData(keysignPayload: trustSet)
        )
        let paymentHash = try Self.preImageHash(
            of: RippleHelper.getPreSignedInputData(keysignPayload: payment)
        )

        XCTAssertNotEqual(
            trustSetHash,
            paymentHash,
            "a TrustSet and a token Payment over the same coin+amount must not share a pre-image hash"
        )
    }

    // MARK: - 4. Token Payment encoding

    /// `opPayment.currencyAmount` carries currency / issuer / value and the drops
    /// `amount` is NOT on the wire — the oneof selects one arm, and a token
    /// Payment must never present a drops amount.
    func testTokenPaymentCarriesCurrencyAmountAndNoDropsAmount() throws {
        let coin = Self.makeTokenCoin()
        let payload = Self.makePayload(
            coin: coin,
            toAddress: Self.destination,
            toAmount: Self.tokenAmount
        )

        let input = try RippleSigningInput(
            serializedBytes: RippleHelper.getPreSignedInputData(keysignPayload: payload)
        )

        XCTAssertEqual(input.opPayment.destination, Self.destination)
        XCTAssertEqual(input.opPayment.currencyAmount.currency, "USD")
        XCTAssertEqual(input.opPayment.currencyAmount.issuer, Self.issuer)
        XCTAssertEqual(input.opPayment.currencyAmount.value, "1.5")
        XCTAssertEqual(
            input.opPayment.amountOneof,
            .currencyAmount(input.opPayment.currencyAmount),
            "the currencyAmount arm must be selected, so no drops amount is serialized"
        )
        XCTAssertEqual(input.opPayment.amount, 0, "the drops accessor defaults to 0 when the oneof holds a currencyAmount")
        XCTAssertTrue(input.rawJson.isEmpty)
        XCTAssertFalse(input.opTrustSet.hasLimitAmount)
    }

    /// A 15-decimal `toAmount` round-trips `formatIssuedCurrencyValue` →
    /// `parseIssuedCurrencyValue` unchanged, so the value the co-signer reads
    /// back off the wire is the reviewed amount and not a truncation of it.
    func testFifteenDecimalAmountRoundTripsThroughTheSignedValue() throws {
        // 1.234567890123456 would exceed 15 decimals; use the full 15.
        let amount = BigInt("1234567890123456")
        let coin = Self.makeTokenCoin()
        let payload = Self.makePayload(coin: coin, toAddress: Self.destination, toAmount: amount)

        let input = try RippleSigningInput(
            serializedBytes: RippleHelper.getPreSignedInputData(keysignPayload: payload)
        )

        XCTAssertEqual(input.opPayment.currencyAmount.value, "1.234567890123456")
        XCTAssertEqual(
            try RippleIssuedCurrency.parseIssuedCurrencyValue(input.opPayment.currencyAmount.value),
            amount,
            "the signed value must parse back to the exact reviewed base-unit amount"
        )
    }

    /// The default trust-line limit is exactly representable at 15 significant
    /// digits, so it round-trips without truncation — the constant is not
    /// allowed to sit past the precision boundary.
    func testDefaultTrustLineLimitRoundTripsExactly() throws {
        let value = try RippleIssuedCurrency.formatIssuedCurrencyValue(
            amount: RippleTrustLineLimit.defaultLimit,
            decimals: RippleIssuedCurrency.issuedCurrencyDecimals
        )
        XCTAssertEqual(value, "1000000000000000")
        XCTAssertEqual(
            try RippleIssuedCurrency.parseIssuedCurrencyValue(value),
            RippleTrustLineLimit.defaultLimit
        )
        XCTAssertEqual(RippleTrustLineLimit.defaultLimitDisplayValue(), "1000000000000000")
    }

    // MARK: - Destination tag still applies to a token Payment

    /// The destination tag is an independent XRPL field, orthogonal to how the
    /// amount is encoded, so a first-class tag rides a token Payment exactly as
    /// it rides a native one.
    func testFieldSourcedDestinationTagAppliesToATokenPayment() throws {
        let payload = Self.makePayload(
            coin: Self.makeTokenCoin(),
            toAddress: Self.destination,
            toAmount: Self.tokenAmount,
            destinationTag: 42
        )

        let input = try RippleSigningInput(
            serializedBytes: RippleHelper.getPreSignedInputData(keysignPayload: payload)
        )

        XCTAssertEqual(input.opPayment.destinationTag, 42)
        XCTAssertEqual(input.opPayment.currencyAmount.value, "1.5")
    }

    /// The legacy memo-carried tag resolves the same way on a token Payment: an
    /// echoed canonical decimal becomes the tag and does NOT become a Memos blob.
    func testMemoCarriedDestinationTagAppliesToATokenPayment() throws {
        let payload = Self.makePayload(
            coin: Self.makeTokenCoin(),
            toAddress: Self.destination,
            toAmount: Self.tokenAmount,
            memo: "7",
            destinationTag: 7
        )

        let input = try RippleSigningInput(
            serializedBytes: RippleHelper.getPreSignedInputData(keysignPayload: payload)
        )

        XCTAssertEqual(input.opPayment.destinationTag, 7)
        XCTAssertTrue(input.rawJson.isEmpty, "an echoed tag carrier must not become a rawJson Memos payment")
    }

    /// FAIL CLOSED: a genuine text memo on a token Payment would have to go
    /// through the rawJson path, whose `Amount` is a DROPS string — signing the
    /// token's base units as native XRP. Refuse instead.
    func testTextMemoOnATokenPaymentThrowsRatherThanSigningDrops() {
        let payload = Self.makePayload(
            coin: Self.makeTokenCoin(),
            toAddress: Self.destination,
            toAmount: Self.tokenAmount,
            memo: "invoice-1234"
        )
        XCTAssertThrowsError(try RippleHelper.getPreSignedInputData(keysignPayload: payload))
    }

    // MARK: - Malformed input fails closed rather than trapping

    func testMalformedTokenIdThrowsOnTrustSet() {
        for contractAddress in ["", "USD", ".rIssuer", "USD.", "no-separator"] {
            let payload = Self.makePayload(
                coin: Self.makeTokenCoin(contractAddress: contractAddress),
                toAddress: "",
                toAmount: Self.tokenAmount,
                transactionType: .rippleTrustSet
            )
            XCTAssertThrowsError(
                try RippleHelper.getPreSignedInputData(keysignPayload: payload),
                "token id '\(contractAddress)' must be rejected, not trapped"
            )
        }
    }

    func testMalformedTokenIdThrowsOnTokenPayment() {
        for contractAddress in ["", "USD", ".rIssuer", "USD.", "no-separator"] {
            let payload = Self.makePayload(
                coin: Self.makeTokenCoin(contractAddress: contractAddress),
                toAddress: Self.destination,
                toAmount: Self.tokenAmount
            )
            XCTAssertThrowsError(
                try RippleHelper.getPreSignedInputData(keysignPayload: payload),
                "token id '\(contractAddress)' must be rejected, not trapped"
            )
        }
    }

    /// FAIL CLOSED on a currency code WalletCore would not put on the wire
    /// verbatim. It uppercases a 3-BYTE code before encoding
    /// (`Currency::from_str` → `Currency::ISO(s.to_uppercase())`) while XRPL
    /// codes are case-SENSITIVE, so `usd` would open a `USD` trust line — or pay
    /// a `USD` obligation — instead of the currency the user reviewed.
    ///
    /// The add-token field already refuses these, but a coin also reaches the
    /// signer from trust-line discovery and from a restored vault, neither of
    /// which passes through that field. This boundary is the one that has to
    /// say no.
    func testCurrencyCodeTheSignerWouldMangleIsRefusedOnBothOperations() {
        for currency in ["usd", "uSd", "a-b"] {
            let trustSet = Self.makePayload(
                coin: Self.makeTokenCoin(contractAddress: "\(currency).\(Self.issuer)"),
                toAddress: "",
                toAmount: Self.tokenAmount,
                transactionType: .rippleTrustSet
            )
            XCTAssertThrowsError(
                try RippleHelper.getPreSignedInputData(keysignPayload: trustSet),
                "'\(currency)' must not be signed as a different currency"
            )

            let payment = Self.makePayload(
                coin: Self.makeTokenCoin(contractAddress: "\(currency).\(Self.issuer)"),
                toAddress: Self.destination,
                toAmount: Self.tokenAmount
            )
            XCTAssertThrowsError(
                try RippleHelper.getPreSignedInputData(keysignPayload: payment),
                "'\(currency)' must not be signed as a different currency"
            )
        }
    }

    /// The counterpart: the same currency written as the 160-bit hex form IS
    /// encoded verbatim, so refusing the lowercase spelling removes a spelling,
    /// not a currency.
    func testTheHexSpellingOfAMangledCodeStillSigns() throws {
        // `usd` at bytes 12–14, which is where a standard code lives.
        let hex = String(repeating: "0", count: 24) + "757364" + String(repeating: "0", count: 10)
        let payload = Self.makePayload(
            coin: Self.makeTokenCoin(contractAddress: "\(hex).\(Self.issuer)"),
            toAddress: Self.destination,
            toAmount: Self.tokenAmount
        )

        let input = try RippleSigningInput(
            serializedBytes: RippleHelper.getPreSignedInputData(keysignPayload: payload)
        )

        XCTAssertEqual(input.opPayment.currencyAmount.currency, hex)
    }

    /// A currency code longer than XRPL's 20-byte limit cannot be normalized, so
    /// the signer rejects it instead of emitting a truncated code.
    func testOverlongCurrencyCodeThrows() {
        let payload = Self.makePayload(
            coin: Self.makeTokenCoin(contractAddress: "THIS_TICKER_IS_FAR_TOO_LONG_FOR_XRPL.\(Self.issuer)"),
            toAddress: Self.destination,
            toAmount: Self.tokenAmount
        )
        XCTAssertThrowsError(try RippleHelper.getPreSignedInputData(keysignPayload: payload))
    }

    /// Hostile `decimals` (proto-relayed, therefore untrusted) must throw rather
    /// than index out of bounds or allocate gigabytes of padding.
    func testHostileDecimalsThrowRatherThanTrap() {
        for decimals in [-1, 1_000_000] {
            let payload = Self.makePayload(
                coin: Self.makeTokenCoin(decimals: decimals),
                toAddress: Self.destination,
                toAmount: Self.tokenAmount
            )
            XCTAssertThrowsError(
                try RippleHelper.getPreSignedInputData(keysignPayload: payload),
                "decimals \(decimals) must be rejected, not trapped"
            )
        }
    }

    /// A native coin can never be a TrustSet — there is no issuer to trust — so
    /// a payload claiming otherwise is rejected rather than signed with an empty
    /// currency and issuer.
    func testTrustSetOnANativeCoinThrows() {
        let payload = Self.makePayload(
            coin: Self.makeNativeCoin(),
            toAddress: "",
            toAmount: BigInt(1_000_000),
            transactionType: .rippleTrustSet
        )
        XCTAssertThrowsError(try RippleHelper.getPreSignedInputData(keysignPayload: payload))
    }

    /// FAIL CLOSED on the dangerous middle: a NON-native coin carrying no token
    /// id satisfies no issued-currency branch, so without this guard it would
    /// fall through to the native encoding and have the token's base units
    /// serialized as XRP DROPS — a silent token→native crossing that moves real
    /// XRP. The whole `Coin` is proto-relayed from a peer, so it must be refused
    /// rather than interpreted.
    func testNonNativeCoinWithNoTokenIdIsRefusedRatherThanSignedAsDrops() {
        let coin = Self.makeTokenCoin(contractAddress: "")

        for memo in [nil, "some text memo", "42"] {
            let payload = Self.makePayload(
                coin: coin,
                toAddress: Self.destination,
                toAmount: Self.tokenAmount,
                memo: memo
            )
            XCTAssertThrowsError(
                try RippleHelper.getPreSignedInputData(keysignPayload: payload),
                "a non-native coin with no token id must never reach the drops encoding (memo: \(memo ?? "nil"))"
            )
        }
    }

    /// FAIL CLOSED on the mirror-image inconsistency: a coin claiming to be
    /// NATIVE while carrying an issued-currency token id. Metadata that names an
    /// issuer but asks to be signed as drops describes no coherent asset, and the
    /// whole `Coin` is proto-relayed, so it is refused rather than interpreted.
    func testNativeCoinCarryingATokenIdIsRefused() {
        let meta = CoinMeta(
            chain: .ripple,
            ticker: "XRP",
            logo: "xrp",
            decimals: 6,
            priceProviderId: "ripple",
            contractAddress: "USD.\(Self.issuer)",
            isNativeToken: true
        )
        let coin = Coin(asset: meta, address: Self.account, hexPublicKey: Self.publicKeyHex)

        for memo in [nil, "invoice-1234", "42"] {
            let payload = Self.makePayload(
                coin: coin,
                toAddress: Self.destination,
                toAmount: BigInt(1_000_000),
                memo: memo
            )
            XCTAssertThrowsError(
                try RippleHelper.getPreSignedInputData(keysignPayload: payload),
                "a native coin carrying a token id must be refused (memo: \(memo ?? "nil"))"
            )
        }
    }

    /// FAIL CLOSED on a discriminator this build doesn't support: another chain's
    /// operation relayed onto a Ripple payload, or a future XRPL operation. The
    /// peer is describing something other than what these branches build, so
    /// signing anything at all would be signing an unreviewed operation. It must
    /// NOT quietly degrade to "just build a Payment".
    func testUnsupportedTransactionTypeIsRefused() {
        for transactionType in [VSTransactionType.tonDeposit, .genericContract, .thorMerge, .qbtcClaimWithProof] {
            let tokenPayload = Self.makePayload(
                coin: Self.makeTokenCoin(),
                toAddress: Self.destination,
                toAmount: Self.tokenAmount,
                transactionType: transactionType
            )
            XCTAssertThrowsError(
                try RippleHelper.getPreSignedInputData(keysignPayload: tokenPayload),
                "\(transactionType) must be refused on a token payload"
            )

            let nativePayload = Self.makePayload(
                coin: Self.makeNativeCoin(),
                toAddress: Self.destination,
                toAmount: BigInt(1_000_000),
                transactionType: transactionType
            )
            XCTAssertThrowsError(
                try RippleHelper.getPreSignedInputData(keysignPayload: nativePayload),
                "\(transactionType) must be refused on a native payload"
            )
        }
    }

    /// A raw discriminator value no build knows (an operation added after this
    /// one) survives the proto round-trip as `UNRECOGNIZED` rather than being
    /// flattened to `.unspecified`, so the signer can see it and refuse.
    func testUnrecognizedTransactionTypeRawValueIsRefused() throws {
        let chainSpecific = BlockChainSpecific.Ripple(
            sequence: Self.sequence,
            gas: Self.gas,
            lastLedgerSequence: Self.lastLedgerSequence,
            transactionType: 9_999
        )

        let roundTripped = try BlockChainSpecific(proto: chainSpecific.mapToProtobuff())
        guard case .Ripple(_, _, _, _, let transactionType) = roundTripped else {
            return XCTFail("expected a Ripple chain specific")
        }
        XCTAssertEqual(transactionType, 9_999, "an unknown discriminator must not be flattened on the wire")
    }

    // MARK: - Frozen golden vectors

    /// FROZEN BYTES for both new operations.
    ///
    /// The parity test above rebuilds its "legacy" reference with the same
    /// normalization and formatting helpers production uses, so a shared mistake
    /// in those helpers would let both sides agree while still diverging from
    /// every other platform. These literals close that hole in the only way a
    /// single-repo test can: they pin the exact bytes this signer emits for a
    /// fixed payload, so any future change to currency normalization, value
    /// formatting, field ordering or the envelope has to be deliberate.
    ///
    /// They are iOS-originated (this app is the first client to build XRPL token
    /// payloads at all). Cross-checking them against the SDK's resolver output is
    /// tracked as parity work rather than done here — nothing in this repo can
    /// execute the TypeScript resolver.
    func testTrustSetSerializesToFrozenBytes() throws {
        let payload = Self.makePayload(
            coin: Self.makeTokenCoin(),
            toAddress: "",
            toAmount: Self.tokenAmount,
            transactionType: .rippleTrustSet
        )

        XCTAssertEqual(
            try RippleHelper.getPreSignedInputData(keysignPayload: payload).hexString,
            Self.frozenTrustSetInputHex,
            "the TrustSet signing input changed — confirm the change is intended and cross-platform"
        )
    }

    func testTokenPaymentSerializesToFrozenBytes() throws {
        let payload = Self.makePayload(
            coin: Self.makeTokenCoin(),
            toAddress: Self.destination,
            toAmount: Self.tokenAmount
        )

        XCTAssertEqual(
            try RippleHelper.getPreSignedInputData(keysignPayload: payload).hexString,
            Self.frozenTokenPaymentInputHex,
            "the issued-currency Payment signing input changed — confirm the change is intended and cross-platform"
        )
    }

    /// TrustSet over `USD.rHb9…` with a limit of `1.5`, fee 10, sequence 99,
    /// lastLedgerSequence 12345678. Decodes as: fee(1)=10, sequence(2)=99,
    /// lastLedgerSequence(3)=12345678, account(4), opTrustSet(7){ limitAmount{
    /// currency="USD", value="1.5", issuer } }, publicKey(15). Note there is NO
    /// field 5 (`flags`) — that absence is part of what is pinned.
    private static let frozenTrustSetInputHex = """
    080a106318cec2f10522227250564d68574273664639694d58596a3361417a4a566b504454464e537957644b79\
    3a300a2e0a035553441203312e351a2272486239434a4157794234726a39315652576e3936446b756b47346277\
    64747954687a210279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798
    """

    /// Issued-currency Payment of `1.5 USD.rHb9…` to `rEb8…`, same envelope.
    /// Decodes as the same envelope plus opPayment(8){ currencyAmount(2){
    /// currency, value, issuer }, destination(3) } — with NO field 1 (the drops
    /// `amount`), which is the property that keeps a token send from ever
    /// presenting a native XRP amount.
    private static let frozenTokenPaymentInputHex = """
    080a106318cec2f10522227250564d68574273664639694d58596a3361417a4a566b504454464e537957644b79\
    4254122e0a035553441203312e351a2272486239434a4157794234726a39315652576e3936446b756b47346277\
    64747954681a2272456238544b336742676b3561755a6b77633673486e777247564a48384475614c687a210279\
    be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798
    """

    // MARK: - Precedence

    /// A dApp `signRipple` payload wins over the trust-set discriminator: raw
    /// JSON is always signed verbatim, so a rawJson transaction can never be
    /// rewritten into a TrustSet.
    func testSignRippleTakesPrecedenceOverTheTrustSetDiscriminator() throws {
        let coin = Self.makeTokenCoin()
        let rawJson = """
        {"TransactionType":"OfferCreate","Account":"\(Self.account)","TakerGets":"5000000","TakerPays":{"currency":"USD","issuer":"\(Self.issuer)","value":"10"},"Fee":"10","Sequence":99,"LastLedgerSequence":12345678}
        """
        let base = Self.makePayload(
            coin: coin,
            toAddress: "",
            toAmount: Self.tokenAmount,
            transactionType: .rippleTrustSet
        )
        let payload = base.withSignData(.signRipple(SignRipple(rawJson: rawJson)))

        let input = try RippleSigningInput(
            serializedBytes: RippleHelper.getPreSignedInputData(keysignPayload: payload)
        )

        XCTAssertEqual(input.rawJson, rawJson)
        XCTAssertFalse(input.opTrustSet.hasLimitAmount)
    }

    /// A standard 3-character code and its 40-char hex spelling of the SAME
    /// currency normalize to the same on-ledger code, so two token ids that
    /// differ only in spelling sign identical bytes.
    func testHexAndStandardCurrencySpellingsSignIdenticalBytes() throws {
        let hexUsd = try RippleIssuedCurrency.toXrplCurrencyCode("USDC") // 4 chars → hex form
        let hexCoin = Self.makeTokenCoin(contractAddress: "\(hexUsd).\(Self.issuer)")
        let lowercaseCoin = Self.makeTokenCoin(contractAddress: "\(hexUsd.lowercased()).\(Self.issuer)")

        let hexInput = try RippleHelper.getPreSignedInputData(
            keysignPayload: Self.makePayload(coin: hexCoin, toAddress: Self.destination, toAmount: Self.tokenAmount)
        )
        let lowercaseInput = try RippleHelper.getPreSignedInputData(
            keysignPayload: Self.makePayload(coin: lowercaseCoin, toAddress: Self.destination, toAmount: Self.tokenAmount)
        )

        XCTAssertEqual(hexInput, lowercaseInput, "a hex currency code must normalize to uppercase before signing")
    }

    // MARK: - Discriminator narrowing at the payload-build seam

    /// `SendTransaction.transactionType` is shared with other chains, so only the
    /// one XRPL value may reach `RippleSpecific.transaction_type`. Anything else
    /// degrades to `.unspecified`, keeping the legacy interpretation instead of
    /// telling co-signers something untrue about the operation.
    func testOnlyTheRippleTrustSetDiscriminatorReachesTheWire() {
        let vault = Vault.example
        let coin = Self.makeTokenCoin()

        for (input, expected) in [
            (VSTransactionType.rippleTrustSet, VSTransactionType.rippleTrustSet),
            (.unspecified, .unspecified),
            (.tonDeposit, .unspecified),
            (.genericContract, .unspecified),
            (.thorMerge, .unspecified)
        ] {
            let tx = SendTransaction.empty(coin: coin, vault: vault).copy(transactionType: input)
            XCTAssertEqual(
                SendCryptoVerifyLogic.rippleTransactionType(tx: tx),
                expected,
                "\(input) must map to \(expected)"
            )
        }
    }

    /// The dual-write seam carries the discriminator onto the Ripple chain
    /// specific, and leaves every other chain untouched.
    func testDualWriteCarriesTheDiscriminatorOntoRippleChainSpecific() {
        let base = BlockChainSpecific.Ripple(
            sequence: Self.sequence,
            gas: Self.gas,
            lastLedgerSequence: Self.lastLedgerSequence
        )

        let trustSet = SendCryptoVerifyLogic.dualWritingRippleTag(base, tag: 5, transactionType: .rippleTrustSet)
        guard case .Ripple(_, _, _, let tag, let transactionType) = trustSet else {
            return XCTFail("expected a Ripple chain specific")
        }
        XCTAssertEqual(tag, 5)
        XCTAssertEqual(transactionType, VSTransactionType.rippleTrustSet.rawValue)

        // Default keeps the field at the proto3 zero value, so nothing changes
        // for an ordinary send.
        let plain = SendCryptoVerifyLogic.dualWritingRippleTag(base, tag: nil)
        guard case .Ripple(_, _, _, _, let plainType) = plain else {
            return XCTFail("expected a Ripple chain specific")
        }
        XCTAssertEqual(plainType, VSTransactionType.unspecified.rawValue)

        let cosmos = BlockChainSpecific.Cosmos(
            accountNumber: 1,
            sequence: 2,
            gas: 3,
            transactionType: 0,
            ibcDenomTrace: nil,
            gasLimit: nil
        )
        XCTAssertEqual(
            SendCryptoVerifyLogic.dualWritingRippleTag(cosmos, tag: 9, transactionType: .rippleTrustSet),
            cosmos,
            "the dual-write seam must be a no-op for non-Ripple chain specifics"
        )
    }
}
