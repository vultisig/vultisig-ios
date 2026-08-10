//
//  RippleSignRippleTests.swift
//  VultisigAppTests
//
//  Pins the SignRipple (dApp XRPL passthrough) keysign path: a dApp-supplied
//  raw XRPL transaction JSON is signed VERBATIM through WalletCore's Ripple
//  rawJson SigningInput (the same envelope the native memo path uses), so every
//  co-signer produces byte-identical bytes; and the co-signer FAILS CLOSED
//  before signing — rejecting any tx whose Account isn't its own vault, or a
//  Payment whose Destination/Amount drifts from the reviewed values. Mirrors
//  the SDK resolver (`core/mpc/keysign/signingInputs/resolvers/ripple.ts`).
//

@testable import VultisigApp
import BigInt
import WalletCore
import XCTest

final class RippleSignRippleTests: XCTestCase {

    // The signing vault's own XRP account + a real secp256k1 public key (the
    // compressed generator point — a valid key the signing-input builder
    // accepts). Reused from the existing Ripple test fixtures.
    private static let account = "rPVMhWBsfF9iMXYj3aAzJVkPDTFNSyWdKy"
    private static let destination = "rEb8TK3gBgk5auZkwc6sHnwrGVJH8DuaLh"
    private static let publicKeyHex = "0279BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798"

    private static let sequence: UInt64 = 99
    private static let gas: UInt64 = 10
    private static let lastLedgerSequence: UInt64 = 12_345_678

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

    /// An issued-currency (IOU) XRP coin whose token id encodes currency+issuer.
    private static func makeIssuedCoin(contractAddress: String, decimals: Int = 15) -> Coin {
        let meta = CoinMeta(
            chain: .ripple,
            ticker: "USD",
            logo: "xrp",
            decimals: decimals,
            priceProviderId: "ripple",
            contractAddress: contractAddress,
            isNativeToken: false
        )
        return Coin(asset: meta, address: account, hexPublicKey: publicKeyHex)
    }

    private static func makePayload(rawJson: String, coin: Coin, toAddress: String, toAmount: BigInt) -> KeysignPayload {
        KeysignPayload(
            coin: coin,
            toAddress: toAddress,
            toAmount: toAmount,
            chainSpecific: .Ripple(sequence: sequence, gas: gas, lastLedgerSequence: lastLedgerSequence),
            utxos: [],
            memo: nil,
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
            signData: .signRipple(SignRipple(rawJson: rawJson))
        )
    }

    private static func nativePaymentJson(
        account: String = account,
        destination: String = destination,
        amount: String = "1000000"
    ) -> String {
        """
        {"TransactionType":"Payment","Account":"\(account)","Destination":"\(destination)","Amount":"\(amount)","Fee":"10","Sequence":99,"LastLedgerSequence":12345678}
        """
    }

    private static func offerCreateJson(account: String = account) -> String {
        """
        {"TransactionType":"OfferCreate","Account":"\(account)","TakerGets":"5000000","TakerPays":{"currency":"USD","issuer":"rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh","value":"10"},"Fee":"10","Sequence":99,"LastLedgerSequence":12345678}
        """
    }

    // MARK: - Verbatim forwarding

    /// The dApp rawJson is forwarded verbatim into the RippleSigningInput
    /// (no opPayment reconstruction), with the envelope fields intact. An
    /// OfferCreate is used to prove non-Payment types survive on the Account
    /// check alone.
    func testSigningInputForwardsRawJsonVerbatim() throws {
        let rawJson = Self.offerCreateJson()
        let payload = Self.makePayload(
            rawJson: rawJson,
            coin: Self.makeNativeCoin(),
            toAddress: "",
            toAmount: 0
        )

        let inputData = try RippleHelper.getPreSignedInputData(keysignPayload: payload)
        let input = try RippleSigningInput(serializedBytes: inputData)

        XCTAssertEqual(input.rawJson, rawJson, "the dApp rawJson must be signed verbatim")
        XCTAssertEqual(input.account, Self.account)
        XCTAssertEqual(input.fee, Int64(Self.gas))
        XCTAssertEqual(input.sequence, UInt32(Self.sequence))
        XCTAssertEqual(input.lastLedgerSequence, UInt32(Self.lastLedgerSequence))
        XCTAssertTrue(input.opPayment.destination.isEmpty, "no opPayment is synthesized on the signRipple path")
    }

    // MARK: - Byte parity (deterministic pre-image hash)

    /// The pre-image hash is deterministic for a fixed rawJson (WalletCore
    /// canonicalizes the JSON, so every co-signer that carries the same rawJson
    /// through the same envelope produces the same signed bytes — the
    /// byte-parity guarantee) and equals the digest of an independently-built
    /// SigningInput carrying the identical rawJson + envelope.
    func testPreSignedImageHashIsDeterministicAndVerbatim() throws {
        let rawJson = Self.nativePaymentJson()
        let payload = Self.makePayload(
            rawJson: rawJson,
            coin: Self.makeNativeCoin(),
            toAddress: Self.destination,
            toAmount: BigInt(1_000_000)
        )

        let first = try RippleHelper.getPreSignedImageHash(keysignPayload: payload)
        let second = try RippleHelper.getPreSignedImageHash(keysignPayload: payload)
        XCTAssertEqual(first.count, 1)
        XCTAssertFalse(try XCTUnwrap(first.first).isEmpty)
        XCTAssertEqual(first, second, "the pre-image hash must be deterministic")

        // Independently build a SigningInput with the same rawJson + envelope
        // and assert the helper signs the identical bytes.
        let publicKey = try XCTUnwrap(PublicKey(data: XCTUnwrap(Data(hexString: Self.publicKeyHex)), type: .secp256k1))
        let reference = RippleSigningInput.with {
            $0.fee = Int64(Self.gas)
            $0.sequence = UInt32(Self.sequence)
            $0.account = Self.account
            $0.publicKey = publicKey.data
            $0.lastLedgerSequence = UInt32(Self.lastLedgerSequence)
            $0.rawJson = rawJson
        }
        let referenceHashes = TransactionCompiler.preImageHashes(coinType: .xrp, txInputData: try reference.serializedData())
        let referenceOutput = try TxCompilerPreSigningOutput(serializedBytes: referenceHashes)
        XCTAssertTrue(referenceOutput.errorMessage.isEmpty)
        XCTAssertEqual(first.first, referenceOutput.dataHash.hexString)
    }

    // MARK: - Fail closed

    func testMissingRawJsonThrows() {
        let payload = Self.makePayload(
            rawJson: "",
            coin: Self.makeNativeCoin(),
            toAddress: Self.destination,
            toAmount: BigInt(1_000_000)
        )
        XCTAssertThrowsError(try RippleHelper.getPreSignedInputData(keysignPayload: payload))
    }

    func testInvalidJsonThrows() {
        let payload = Self.makePayload(
            rawJson: "not-a-json {{{",
            coin: Self.makeNativeCoin(),
            toAddress: Self.destination,
            toAmount: BigInt(1_000_000)
        )
        XCTAssertThrowsError(try RippleHelper.getPreSignedInputData(keysignPayload: payload))
    }

    func testNonObjectJsonThrows() {
        let payload = Self.makePayload(
            rawJson: "\"just a string\"",
            coin: Self.makeNativeCoin(),
            toAddress: Self.destination,
            toAmount: BigInt(1_000_000)
        )
        XCTAssertThrowsError(try RippleHelper.getPreSignedInputData(keysignPayload: payload))
    }

    /// FAIL CLOSED: a transaction that spends an account other than this vault
    /// is rejected before signing.
    func testAccountMismatchThrows() {
        let rawJson = Self.nativePaymentJson(account: Self.destination) // wrong Account
        let payload = Self.makePayload(
            rawJson: rawJson,
            coin: Self.makeNativeCoin(),
            toAddress: Self.destination,
            toAmount: BigInt(1_000_000)
        )
        XCTAssertThrowsError(try RippleHelper.getPreSignedInputData(keysignPayload: payload))
    }

    func testPaymentDestinationMismatchThrows() {
        let rawJson = Self.nativePaymentJson(destination: "rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh")
        let payload = Self.makePayload(
            rawJson: rawJson,
            coin: Self.makeNativeCoin(),
            toAddress: Self.destination, // reviewed destination differs from the tx
            toAmount: BigInt(1_000_000)
        )
        XCTAssertThrowsError(try RippleHelper.getPreSignedInputData(keysignPayload: payload))
    }

    func testPaymentAmountMismatchThrows() {
        let rawJson = Self.nativePaymentJson(amount: "999") // tx amount != reviewed toAmount
        let payload = Self.makePayload(
            rawJson: rawJson,
            coin: Self.makeNativeCoin(),
            toAddress: Self.destination,
            toAmount: BigInt(1_000_000)
        )
        XCTAssertThrowsError(try RippleHelper.getPreSignedInputData(keysignPayload: payload))
    }

    /// A native-coin Payment whose Amount is an issued-currency object (not a
    /// drops string) must be rejected.
    func testNativePaymentWithIssuedAmountThrows() {
        let rawJson = """
        {"TransactionType":"Payment","Account":"\(Self.account)","Destination":"\(Self.destination)","Amount":{"currency":"USD","issuer":"rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh","value":"1"},"Fee":"10","Sequence":99,"LastLedgerSequence":12345678}
        """
        let payload = Self.makePayload(
            rawJson: rawJson,
            coin: Self.makeNativeCoin(),
            toAddress: Self.destination,
            toAmount: BigInt(1_000_000)
        )
        XCTAssertThrowsError(try RippleHelper.getPreSignedInputData(keysignPayload: payload))
    }

    /// A non-Payment type (OfferCreate) is NOT bound to toAddress/toAmount — it
    /// passes on the Account check alone, so a legitimate offer is never
    /// false-rejected.
    func testOfferCreatePassesOnAccountCheckAlone() throws {
        let payload = Self.makePayload(
            rawJson: Self.offerCreateJson(),
            coin: Self.makeNativeCoin(),
            toAddress: "",
            toAmount: 0
        )
        XCTAssertNoThrow(try RippleHelper.getPreSignedInputData(keysignPayload: payload))
    }

    // MARK: - Currency-code gate applies to every transaction type

    //  wallet-core uppercases a 3-byte currency code before encoding — measured
    //  on this exact rawJson path in `RippleCurrencyCodeCaseTests`, not inferred
    //  from the typed path. So a code it would alter has to be refused wherever
    //  it appears, not only in `Payment.Amount`.
    //
    //  `testOfferCreatePassesOnAccountCheckAlone` above stays as-is and is still
    //  correct: an offer with an ALREADY-uppercase code is not false-rejected.
    //  These are its negative controls — the case that fixture never exercised.

    private static func offerCreateJson(takerPaysCurrency: String) -> String {
        """
        {"TransactionType":"OfferCreate","Account":"\(account)","TakerGets":"5000000","TakerPays":{"currency":"\(takerPaysCurrency)","issuer":"rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh","value":"10"},"Fee":"10","Sequence":99,"LastLedgerSequence":12345678}
        """
    }

    private static func trustSetJson(limitCurrency: String) -> String {
        """
        {"TransactionType":"TrustSet","Account":"\(account)","LimitAmount":{"currency":"\(limitCurrency)","issuer":"rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh","value":"1000"},"Fee":"10","Sequence":99,"LastLedgerSequence":12345678}
        """
    }

    private func assertRefused(_ rawJson: String, _ message: String) {
        let payload = Self.makePayload(
            rawJson: rawJson,
            coin: Self.makeNativeCoin(),
            toAddress: "",
            toAmount: 0
        )
        XCTAssertThrowsError(try RippleHelper.getPreSignedInputData(keysignPayload: payload), message)
    }

    /// A trust line reviewed as `usd` would be opened as `USD` — a different
    /// line than the one shown, reserving against a currency the co-signer
    /// never approved.
    func testTrustSetWithAMangledLimitCurrencyIsRefused() {
        assertRefused(
            Self.trustSetJson(limitCurrency: "usd"),
            "a TrustSet LimitAmount the signer would alter must be refused"
        )
    }

    func testTrustSetWithAnUppercaseLimitCurrencyIsAccepted() throws {
        let payload = Self.makePayload(
            rawJson: Self.trustSetJson(limitCurrency: "USD"),
            coin: Self.makeNativeCoin(),
            toAddress: "",
            toAmount: 0
        )
        XCTAssertNoThrow(try RippleHelper.getPreSignedInputData(keysignPayload: payload))
    }

    /// An offer reviewed against `usd` would be placed against `USD` — a
    /// different currency pair than the one shown.
    func testOfferCreateWithAMangledTakerPaysCurrencyIsRefused() {
        assertRefused(
            Self.offerCreateJson(takerPaysCurrency: "usd"),
            "an OfferCreate TakerPays the signer would alter must be refused"
        )
    }

    func testOfferCreateWithMixedCaseCurrencyIsRefused() {
        assertRefused(
            Self.offerCreateJson(takerPaysCurrency: "UsD"),
            "mixed case is altered just as lowercase is"
        )
    }

    // MARK: - The gate judges the RAW code, not a normalised one

    //  `toXrplCurrencyCode` TRIMS whitespace and then ASCII-packs anything that
    //  is neither 3 characters nor 40 hex digits; wallet-core does neither and
    //  classifies the raw string by BYTE length (measured in
    //  `RippleCurrencyCodeCaseTests`). Normalising before classifying therefore
    //  judged a currency the signer never receives.
    //
    //  These are the exposed fields: TrustSet `LimitAmount` and OfferCreate
    //  `TakerGets`/`TakerPays` have no second gate — the walk is the only thing
    //  standing between the co-signer and the ledger — and a trailing space is
    //  invisible on the Verify screen.

    private static let hexRlusd = "524C555344000000000000000000000000000000"

    /// `Ab ` normalised to a 2-character ticker, ASCII-packed to `4162…` and
    /// passed the old gate, while wallet-core read 3 raw bytes as an ISO code
    /// and signed `AB ` — a different trust line than the reviewed one.
    func testTrustSetWithAWhitespaceEdgedLimitCurrencyIsRefused() {
        assertRefused(
            Self.trustSetJson(limitCurrency: "Ab "),
            "a LimitAmount code whose raw bytes the signer would alter must be refused"
        )
    }

    func testOfferCreateWithAWhitespaceEdgedTakerPaysCurrencyIsRefused() {
        assertRefused(
            Self.offerCreateJson(takerPaysCurrency: "Ab "),
            "a TakerPays code whose raw bytes the signer would alter must be refused"
        )
    }

    /// Leading whitespace splits the two classifications the same way trailing
    /// whitespace does.
    func testOfferCreateWithALeadingSpaceTakerPaysCurrencyIsRefused() {
        assertRefused(
            Self.offerCreateJson(takerPaysCurrency: " AB"),
            "trimming is the asymmetry, not the side the whitespace sits on"
        )
    }

    /// No whitespace involved: a single 3-BYTE character is an ISO code to the
    /// signer and an ASCII-packed hex code to the normaliser.
    func testTrustSetWithAThreeByteNonAsciiLimitCurrencyIsRefused() {
        assertRefused(
            Self.trustSetJson(limitCurrency: "\u{20AC}"),
            "byte length, not character count, is what the signer classifies on"
        )
    }

    /// A code the signer cannot classify at all is refused here rather than
    /// ASCII-packed into one the signer never receives.
    func testTrustSetWithAnUnpackableLimitCurrencyIsRefused() {
        assertRefused(
            Self.trustSetJson(limitCurrency: "RLUSD"),
            "a 5-character code is not an on-ledger currency and wallet-core refuses it outright"
        )
    }

    /// Positive control for the tightening: the 40-character hex form stays
    /// expressible in EITHER case, so nothing legitimate was removed —
    /// wallet-core decodes hex case-insensitively.
    func testTrustSetWithAHexLimitCurrencyIsAcceptedInEitherCase() throws {
        for limitCurrency in [Self.hexRlusd, Self.hexRlusd.lowercased()] {
            let payload = Self.makePayload(
                rawJson: Self.trustSetJson(limitCurrency: limitCurrency),
                coin: Self.makeNativeCoin(),
                toAddress: "",
                toAmount: 0
            )
            XCTAssertNoThrow(
                try RippleHelper.getPreSignedInputData(keysignPayload: payload),
                "the hex spelling must stay expressible: \(limitCurrency)"
            )
        }
    }

    // MARK: - SendMax / DeliverMin are gated too

    private static func paymentJson(field: String, currency: String) -> String {
        """
        {"TransactionType":"Payment","Account":"\(account)","Destination":"\(destination)","Amount":"1000000","\(field)":{"currency":"\(currency)","issuer":"rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh","value":"100"},"Fee":"10","Sequence":99,"LastLedgerSequence":12345678}
        """
    }

    /// A `Payment` has a SECOND gate: `bindPaymentToReviewedValues` also demands
    /// `Destination == toAddress` and `Amount == toAmount`. So a fixture whose
    /// reviewed values do not match its JSON is refused whatever the currency
    /// walk does, and would stay green if the walk stopped covering SendMax /
    /// DeliverMin entirely.
    ///
    /// These payloads therefore bind CLEANLY — reviewed destination and amount
    /// equal to the fixture's — so the currency walk is the only thing left that
    /// can reject. `testPaymentWithAnUppercase…CurrencyIsAccepted` below is the
    /// control that proves the binding really does pass.
    private func assertBoundPaymentRefused(_ rawJson: String, _ message: String) {
        let payload = Self.makePayload(
            rawJson: rawJson,
            coin: Self.makeNativeCoin(),
            toAddress: Self.destination,
            toAmount: BigInt(1_000_000)
        )
        XCTAssertThrowsError(try RippleHelper.getPreSignedInputData(keysignPayload: payload), message)
    }

    private func assertBoundPaymentAccepted(_ rawJson: String, _ message: String) {
        let payload = Self.makePayload(
            rawJson: rawJson,
            coin: Self.makeNativeCoin(),
            toAddress: Self.destination,
            toAmount: BigInt(1_000_000)
        )
        XCTAssertNoThrow(try RippleHelper.getPreSignedInputData(keysignPayload: payload), message)
    }

    /// `SendMax` is a spend authorisation shown on the Verify screen. Displaying
    /// `100 usd` and signing `100 USD` authorises a different asset entirely, and
    /// it sits outside the `Amount` branch the original gate covered.
    func testPaymentWithAMangledSendMaxCurrencyIsRefused() {
        assertBoundPaymentRefused(
            Self.paymentJson(field: "SendMax", currency: "usd"),
            "a SendMax the signer would alter must be refused"
        )
    }

    func testPaymentWithAMangledDeliverMinCurrencyIsRefused() {
        assertBoundPaymentRefused(
            Self.paymentJson(field: "DeliverMin", currency: "usd"),
            "a DeliverMin the signer would alter must be refused"
        )
    }

    /// The controls that make the two refusals above load-bearing: the same
    /// fixtures with an already-uppercase code SIGN. Without these, a refusal
    /// proves only that something objected, not that the currency walk did.
    func testPaymentWithAnUppercaseSendMaxCurrencyIsAccepted() {
        assertBoundPaymentAccepted(
            Self.paymentJson(field: "SendMax", currency: "USD"),
            "the payload binds, so only the currency can be the reason for a refusal"
        )
    }

    func testPaymentWithAnUppercaseDeliverMinCurrencyIsAccepted() {
        assertBoundPaymentAccepted(
            Self.paymentJson(field: "DeliverMin", currency: "USD"),
            "the payload binds, so only the currency can be the reason for a refusal"
        )
    }

    /// A whitespace-edged 3-byte code is refused in SendMax / DeliverMin too —
    /// the raw-string judgement is not special-cased to any field.
    func testPaymentWithAWhitespaceEdgedSendMaxCurrencyIsRefused() {
        assertBoundPaymentRefused(
            Self.paymentJson(field: "SendMax", currency: "Ab "),
            "a SendMax code whose raw bytes the signer would alter must be refused"
        )
    }

    /// The walk is structural, not a field allowlist, so a term this signer does
    /// not know about is covered by default rather than silently exempt.
    func testAMangledCurrencyNestedInAnUnknownFieldIsRefused() {
        let rawJson = """
        {"TransactionType":"OfferCreate","Account":"\(Self.account)","TakerGets":"5000000","TakerPays":{"currency":"USD","issuer":"rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh","value":"10"},"SomeFutureField":[{"nested":{"currency":"usd","issuer":"rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh","value":"1"}}],"Fee":"10","Sequence":99,"LastLedgerSequence":12345678}
        """
        assertRefused(rawJson, "an unknown field carrying a mangled code must still be refused")
    }

    // MARK: - Issued-currency Payment binding

    /// A cross-currency Payment whose issued-currency Amount matches the
    /// reviewed coin's token id (currency + issuer + numeric value) binds
    /// successfully.
    func testIssuedCurrencyPaymentBinds() throws {
        let issuer = "rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh"
        let coin = Self.makeIssuedCoin(contractAddress: "USD.\(issuer)", decimals: 15)
        // 1.5 USD at 15 decimals.
        let toAmount = BigInt("1500000000000000")
        let rawJson = """
        {"TransactionType":"Payment","Account":"\(Self.account)","Destination":"\(Self.destination)","Amount":{"currency":"USD","issuer":"\(issuer)","value":"1.5"},"Fee":"10","Sequence":99,"LastLedgerSequence":12345678}
        """
        let payload = Self.makePayload(rawJson: rawJson, coin: coin, toAddress: Self.destination, toAmount: toAmount)

        let input = try RippleSigningInput(serializedBytes: RippleHelper.getPreSignedInputData(keysignPayload: payload))
        XCTAssertEqual(input.rawJson, rawJson)
    }

    /// The rawJson goes to WalletCore verbatim, and it uppercases a 3-BYTE
    /// currency code before encoding while XRPL codes are case-SENSITIVE. Two
    /// sides agreeing on `usd` is therefore NOT enough — the ledger would still
    /// receive `USD`, a currency neither the dApp nor the reviewer named. Refuse.
    func testIssuedCurrencyPaymentWhoseCodeTheSignerWouldMangleThrows() {
        let issuer = "rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh"
        let coin = Self.makeIssuedCoin(contractAddress: "usd.\(issuer)", decimals: 15)
        let rawJson = """
        {"TransactionType":"Payment","Account":"\(Self.account)","Destination":"\(Self.destination)","Amount":{"currency":"usd","issuer":"\(issuer)","value":"1.5"},"Fee":"10","Sequence":99,"LastLedgerSequence":12345678}
        """
        let payload = Self.makePayload(
            rawJson: rawJson,
            coin: coin,
            toAddress: Self.destination,
            toAmount: BigInt("1500000000000000")
        )
        XCTAssertThrowsError(
            try RippleHelper.getPreSignedInputData(keysignPayload: payload),
            "matching spellings must not license signing a currency the encoder rewrites"
        )
    }

    func testIssuedCurrencyPaymentIssuerMismatchThrows() {
        let coin = Self.makeIssuedCoin(contractAddress: "USD.rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh", decimals: 15)
        let rawJson = """
        {"TransactionType":"Payment","Account":"\(Self.account)","Destination":"\(Self.destination)","Amount":{"currency":"USD","issuer":"rDifferentIssuerAAAAAAAAAAAAAAAAAAA","value":"1.5"},"Fee":"10","Sequence":99,"LastLedgerSequence":12345678}
        """
        let payload = Self.makePayload(
            rawJson: rawJson,
            coin: coin,
            toAddress: Self.destination,
            toAmount: BigInt("1500000000000000")
        )
        XCTAssertThrowsError(try RippleHelper.getPreSignedInputData(keysignPayload: payload))
    }

    func testIssuedCurrencyPaymentValueMismatchThrows() {
        let issuer = "rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh"
        let coin = Self.makeIssuedCoin(contractAddress: "USD.\(issuer)", decimals: 15)
        let rawJson = """
        {"TransactionType":"Payment","Account":"\(Self.account)","Destination":"\(Self.destination)","Amount":{"currency":"USD","issuer":"\(issuer)","value":"2.5"},"Fee":"10","Sequence":99,"LastLedgerSequence":12345678}
        """
        let payload = Self.makePayload(
            rawJson: rawJson,
            coin: coin,
            toAddress: Self.destination,
            toAmount: BigInt("1500000000000000") // reviewed 1.5 != tx 2.5
        )
        XCTAssertThrowsError(try RippleHelper.getPreSignedInputData(keysignPayload: payload))
    }

    /// An issued-currency value with an absurd exponent must fail closed (be
    /// rejected as a mismatch) rather than driving an unbounded BigInt power.
    func testIssuedCurrencyPaymentAbsurdExponentThrows() {
        let issuer = "rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh"
        let coin = Self.makeIssuedCoin(contractAddress: "USD.\(issuer)", decimals: 15)
        let rawJson = """
        {"TransactionType":"Payment","Account":"\(Self.account)","Destination":"\(Self.destination)","Amount":{"currency":"USD","issuer":"\(issuer)","value":"1e999999"},"Fee":"10","Sequence":99,"LastLedgerSequence":12345678}
        """
        let payload = Self.makePayload(
            rawJson: rawJson,
            coin: coin,
            toAddress: Self.destination,
            toAmount: BigInt("1500000000000000")
        )
        XCTAssertThrowsError(try RippleHelper.getPreSignedInputData(keysignPayload: payload))
    }

    // MARK: - tfPartialPayment: the bound Amount must still bound delivery

    //  `bindPaymentToReviewedValues` only means anything while `Amount` is a
    //  delivery. `tfPartialPayment` (0x00020000) makes it a ceiling instead, so
    //  every fixture here binds CLEANLY — reviewed destination and amount equal
    //  to the JSON's — and the new gate is the only thing that can reject.

    /// Builds a native `Payment` for `destination` / 1 XRP with an arbitrary
    /// tail of extra fields, so a fixture differs from the accepted control in
    /// exactly the terms under test.
    private static func boundPaymentJson(extraFields: String = "") -> String {
        """
        {"TransactionType":"Payment","Account":"\(account)","Destination":"\(destination)","Amount":"1000000","SendMax":"999999999"\(extraFields),"Fee":"10","Sequence":99,"LastLedgerSequence":12345678}
        """
    }

    /// The acceptance case. Every pre-existing gate passes — `Account` is the
    /// vault, `Destination` is the reviewed address, `Amount` is the reviewed
    /// amount byte for byte — and the transaction can still settle for dust
    /// while spending the whole `SendMax`.
    func testPartialPaymentWithoutDeliverMinIsRefused() {
        assertBoundPaymentRefused(
            Self.boundPaymentJson(extraFields: ",\"Flags\":131072"),
            "a tfPartialPayment Payment with no DeliverMin floor must be refused before signing"
        )
    }

    /// A floor restores something for the reviewed amount to mean, so a partial
    /// payment carrying one is forwarded unchanged. Partial payments are
    /// legitimate; only unfloored ones are not.
    func testPartialPaymentWithDeliverMinIsForwarded() throws {
        let rawJson = Self.boundPaymentJson(extraFields: ",\"DeliverMin\":\"900000\",\"Flags\":131072")
        let payload = Self.makePayload(
            rawJson: rawJson,
            coin: Self.makeNativeCoin(),
            toAddress: Self.destination,
            toAmount: BigInt(1_000_000)
        )

        let input = try RippleSigningInput(serializedBytes: RippleHelper.getPreSignedInputData(keysignPayload: payload))
        XCTAssertEqual(input.rawJson, rawJson, "a floored partial payment must still be signed verbatim")
    }

    /// A `DeliverMin` that is present but floors nothing must not be mistaken
    /// for one that does. Each of these satisfies "the field is there".
    func testPartialPaymentWithAHollowDeliverMinIsRefused() {
        let hollowFloors = [
            "null",
            "{}",
            "\"0\"",
            "\"-1\"",
            "\"not-a-number\"",
            "123456",
            "{\"currency\":\"USD\",\"issuer\":\"rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh\"}",
            "{\"currency\":\"USD\",\"issuer\":\"rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh\",\"value\":\"0\"}"
        ]
        for floor in hollowFloors {
            assertBoundPaymentRefused(
                Self.boundPaymentJson(extraFields: ",\"DeliverMin\":\(floor),\"Flags\":131072"),
                "a DeliverMin of \(floor) bounds nothing and must not license a partial payment"
            )
        }
    }

    /// An issued-currency `DeliverMin` is a real floor and must be accepted in
    /// the same way a drops one is.
    func testPartialPaymentWithAnIssuedDeliverMinFloorIsForwarded() throws {
        let issuer = "rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh"
        let coin = Self.makeIssuedCoin(contractAddress: "USD.\(issuer)", decimals: 15)
        let rawJson = """
        {"TransactionType":"Payment","Account":"\(Self.account)","Destination":"\(Self.destination)","Amount":{"currency":"USD","issuer":"\(issuer)","value":"1.5"},"DeliverMin":{"currency":"USD","issuer":"\(issuer)","value":"1.4"},"Flags":131072,"Fee":"10","Sequence":99,"LastLedgerSequence":12345678}
        """
        let payload = Self.makePayload(
            rawJson: rawJson,
            coin: coin,
            toAddress: Self.destination,
            toAmount: BigInt("1500000000000000")
        )

        let input = try RippleSigningInput(serializedBytes: RippleHelper.getPreSignedInputData(keysignPayload: payload))
        XCTAssertEqual(input.rawJson, rawJson)
    }

    /// A `Flags` value the XRPL codec could not have encoded as a uint32 is
    /// refused rather than read as "nothing set" — it may carry the very bit
    /// being checked. `{"tfPartialPayment": true}` is the object sugar some
    /// client libraries accept.
    func testFlagsThatAreNotAUint32AreRefused() {
        let undecodable = [
            "{\"tfPartialPayment\":true}",
            "\"131072\"",
            "true",
            "-1",
            "131072.5",
            "4294967296",
            "null",
            "[131072]"
        ]
        for flags in undecodable {
            assertBoundPaymentRefused(
                Self.boundPaymentJson(extraFields: ",\"Flags\":\(flags)"),
                "an undecodable Flags value must be refused, not read as zero: \(flags)"
            )
        }
    }

    /// `tfFullyCanonicalSig` (0x80000000) sits above `INT32_MAX`. The uint32
    /// bound must not clip it into a rejection.
    func testFullyCanonicalSigFlagIsForwarded() {
        assertBoundPaymentAccepted(
            Self.boundPaymentJson(extraFields: ",\"Flags\":2147483648"),
            "a flag above INT32_MAX must survive the uint32 bound"
        )
    }

    /// The zero control: the same fixture without any `Flags` binds cleanly, so
    /// the rejections above are attributable to the flag and nothing else.
    func testBoundPaymentWithNoFlagsIsAccepted() {
        assertBoundPaymentAccepted(
            Self.boundPaymentJson(),
            "the fixture must bind cleanly once the flag is removed"
        )
    }

    /// 0x00020000 is namespace-sensitive: on an `OfferCreate` it is
    /// `tfImmediateOrCancel`, which has nothing to do with delivery. Reading it
    /// as partial payment there would false-reject a legitimate offer.
    func testPartialPaymentBitOnAnOfferCreateIsNotRefused() {
        let rawJson = """
        {"TransactionType":"OfferCreate","Account":"\(Self.account)","TakerGets":"5000000","TakerPays":{"currency":"USD","issuer":"rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh","value":"10"},"Flags":131072,"Fee":"10","Sequence":99,"LastLedgerSequence":12345678}
        """
        let payload = Self.makePayload(
            rawJson: rawJson,
            coin: Self.makeNativeCoin(),
            toAddress: "",
            toAmount: 0
        )
        XCTAssertNoThrow(
            try RippleHelper.getPreSignedInputData(keysignPayload: payload),
            "tfImmediateOrCancel on an offer must not be read as a partial payment"
        )
    }

    /// `Paths` is legitimate on a cross-currency payment — refusing it would
    /// break real DEX flows. It is surfaced on the review screen instead.
    func testPaymentCarryingPathsIsNotRefused() {
        let paths = "[[{\"currency\":\"USD\",\"issuer\":\"rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh\"}]]"
        assertBoundPaymentAccepted(
            Self.boundPaymentJson(extraFields: ",\"Paths\":\(paths)"),
            "dApp-supplied Paths must be surfaced, not refused"
        )
    }

    // MARK: - Native path unchanged

    /// With no signRipple, RippleHelper still builds the native opPayment from
    /// toAddress / toAmount, unchanged.
    func testNativeXrpPathUnchanged() throws {
        let payload = KeysignPayload(
            coin: Self.makeNativeCoin(),
            toAddress: Self.destination,
            toAmount: BigInt(1_000_000),
            chainSpecific: .Ripple(sequence: Self.sequence, gas: Self.gas, lastLedgerSequence: Self.lastLedgerSequence),
            utxos: [],
            memo: nil,
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

        let input = try RippleSigningInput(serializedBytes: RippleHelper.getPreSignedInputData(keysignPayload: payload))
        XCTAssertEqual(input.opPayment.destination, Self.destination)
        XCTAssertEqual(input.opPayment.amount, 1_000_000)
        XCTAssertTrue(input.rawJson.isEmpty, "the native path must not take the rawJson branch")
    }
}
