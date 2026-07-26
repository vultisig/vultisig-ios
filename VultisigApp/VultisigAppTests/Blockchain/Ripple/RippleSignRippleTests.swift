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
