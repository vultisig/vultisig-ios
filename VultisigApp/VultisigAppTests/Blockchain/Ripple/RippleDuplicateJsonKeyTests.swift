//
//  RippleDuplicateJsonKeyTests.swift
//  VultisigAppTests
//
//  Pins how the two JSON parsers standing either side of the dApp signing gate
//  resolve a DUPLICATE key — and that the gate refuses the rawJson when they
//  cannot agree.
//
//  `dappSigningInput` decides what may be signed from the object
//  `JSONSerialization` produces; wallet-core then signs the same rawJson text
//  through its OWN parser. Duplicate keys are legal JSON and RFC 8259 leaves the
//  winner unspecified, so the two are free to disagree.
//
//  They do. Measured here rather than assumed, on the two things that actually
//  settle it — the decoded object for `JSONSerialization`, the encoded bytes for
//  wallet-core:
//
//      JSONSerialization  →  keeps the FIRST occurrence
//      wallet-core        →  keeps the LAST occurrence
//
//  So every check in the signing gate can be passed by one value and signed with
//  another. `Destination` is the sharp end: bind against the reviewed address,
//  pay a different one. The gate refuses any repeated key outright, and these
//  tests pin both the divergence and the refusal, so a future parser change
//  surfaces here instead of silently reopening the gap.
//

@testable import VultisigApp
import BigInt
import WalletCore
import XCTest

final class RippleDuplicateJsonKeyTests: XCTestCase {

    /// The signing vault's own XRP account, and two other valid XRPL addresses.
    private static let account = "rPVMhWBsfF9iMXYj3aAzJVkPDTFNSyWdKy"
    private static let destination = "rEb8TK3gBgk5auZkwc6sHnwrGVJH8DuaLh"
    private static let otherAddress = "rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh"

    private static let publicKeyHex = "0279BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798"
    private static let privateKeyHex = "acf1bbf6264e699da0cc65d17ac03fcca6ded1522d19529df70faa5f2d833f89"

    // MARK: - wallet-core measurement helpers

    private func makeKey() throws -> PrivateKey {
        try XCTUnwrap(PrivateKey(data: try XCTUnwrap(Data(hexString: Self.privateKeyHex))))
    }

    /// Derived from the signing key rather than hardcoded: wallet-core rejects an
    /// input whose `account` does not belong to the key it signs with.
    private func derivedAccount(_ key: PrivateKey) -> String {
        AnyAddress(publicKey: key.getPublicKeySecp256k1(compressed: true), coin: .xrp).description
    }

    /// Signs `rawJson` through wallet-core and returns the encoded transaction.
    /// The encoded bytes are the only thing that can say which value the signer
    /// kept — the collapsed object cannot.
    private func encoded(rawJson build: (String) -> String) throws -> Data {
        let key = try makeKey()
        let input = RippleSigningInput.with {
            $0.fee = 10
            $0.sequence = 99
            $0.account = derivedAccount(key)
            $0.lastLedgerSequence = 12_345_678
            $0.privateKey = key.data
            $0.rawJson = build(derivedAccount(key))
        }
        let output: RippleSigningOutput = AnySigner.sign(input: input, coin: .xrp)
        XCTAssertTrue(output.errorMessage.isEmpty, "wallet-core refused to sign: \(output.errorMessage)")
        XCTAssertFalse(output.encoded.isEmpty)
        return output.encoded
    }

    /// A Payment whose `Amount` object carries `currencies` in the order given —
    /// one entry is an ordinary object, two is a duplicate key.
    private static func paymentAmount(currencies: [String]) -> (String) -> String {
        { signingAccount in
            let fields = currencies.map { "\"currency\":\"\($0)\"" }
                + ["\"issuer\":\"\(otherAddress)\"", "\"value\":\"1\""]
            return """
            {"TransactionType":"Payment","Account":"\(signingAccount)","Destination":"\(destination)",\
            "Amount":{\(fields.joined(separator: ","))}}
            """
        }
    }

    /// A native Payment carrying `destinations` in the order given.
    private static func paymentDestinations(_ destinations: [String]) -> (String) -> String {
        { signingAccount in
            let fields = destinations.map { "\"Destination\":\"\($0)\"" }
            return """
            {"TransactionType":"Payment","Account":"\(signingAccount)",\
            \(fields.joined(separator: ",")),"Amount":"1000000"}
            """
        }
    }

    // MARK: - The two parsers disagree

    /// `JSONSerialization` — the parser every check in the signing gate reads
    /// from — keeps the FIRST value.
    func testJsonSerializationKeepsTheFirstDuplicateValue() throws {
        let json = """
        {"Amount":{"currency":"USD","issuer":"\(Self.otherAddress)","value":"1","currency":"EUR"}}
        """
        let parsed = try JSONSerialization.jsonObject(with: XCTUnwrap(json.data(using: .utf8)))
        let amount = try XCTUnwrap((parsed as? [String: Any])?["Amount"] as? [String: Any])

        XCTAssertEqual(amount["currency"] as? String, "USD", "JSONSerialization keeps the first occurrence")
    }

    /// wallet-core — the parser that decides what reaches the ledger — keeps the
    /// LAST value. Proved by byte equality of the WHOLE encoded transaction
    /// against the single-keyed spelling of each candidate: a substring search
    /// would be heuristic, and this is the measurement the gate rests on.
    func testWalletCoreKeepsTheLastDuplicateValue() throws {
        let duplicated = try encoded(rawJson: Self.paymentAmount(currencies: ["USD", "EUR"]))
        let firstOnly = try encoded(rawJson: Self.paymentAmount(currencies: ["USD"]))
        let lastOnly = try encoded(rawJson: Self.paymentAmount(currencies: ["EUR"]))

        // Control: the comparison has to be sensitive to the currency at all, or
        // "identical bytes" would prove nothing.
        XCTAssertNotEqual(firstOnly, lastOnly, "the encoding must depend on the currency")

        XCTAssertEqual(duplicated, lastOnly, "wallet-core keeps the last occurrence")
        XCTAssertNotEqual(duplicated, firstOnly, "wallet-core does NOT keep the first occurrence")
    }

    /// The sharp end of the divergence, measured on the field that moves money:
    /// a repeated `Destination` is bound by this app against the first address
    /// and paid by wallet-core to the second.
    func testWalletCoreSendsADuplicatedDestinationToTheLastAddress() throws {
        let duplicated = try encoded(rawJson: Self.paymentDestinations([Self.destination, Self.otherAddress]))
        let firstOnly = try encoded(rawJson: Self.paymentDestinations([Self.destination]))
        let lastOnly = try encoded(rawJson: Self.paymentDestinations([Self.otherAddress]))

        XCTAssertNotEqual(firstOnly, lastOnly, "the encoding must depend on the destination")
        XCTAssertEqual(duplicated, lastOnly, "the funds would go to the address this app never reviewed")
        XCTAssertNotEqual(duplicated, firstOnly)
    }

    // MARK: - The gate refuses what it cannot read unambiguously

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

    private static func makePayload(rawJson: String, toAddress: String, toAmount: BigInt) -> KeysignPayload {
        KeysignPayload(
            coin: makeNativeCoin(),
            toAddress: toAddress,
            toAmount: toAmount,
            chainSpecific: .Ripple(sequence: 99, gas: 10, lastLedgerSequence: 12_345_678),
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

    /// A repeated `Destination` binds against the reviewed address under
    /// `JSONSerialization` and pays the other one on the ledger. Refused.
    func testADuplicateDestinationIsRefused() {
        let rawJson = """
        {"TransactionType":"Payment","Account":"\(Self.account)","Destination":"\(Self.destination)",\
        "Amount":"1000000","Destination":"\(Self.otherAddress)"}
        """
        let payload = Self.makePayload(rawJson: rawJson, toAddress: Self.destination, toAmount: BigInt(1_000_000))

        XCTAssertThrowsError(
            try RippleHelper.getPreSignedInputData(keysignPayload: payload),
            "the reviewed Destination is not the one that would be signed"
        )
    }

    /// Control for the test above: the SAME payload with the duplicate removed
    /// signs. Without it, the refusal could be coming from anywhere.
    func testTheSamePayloadWithoutTheDuplicateIsAccepted() {
        let rawJson = """
        {"TransactionType":"Payment","Account":"\(Self.account)","Destination":"\(Self.destination)",\
        "Amount":"1000000"}
        """
        let payload = Self.makePayload(rawJson: rawJson, toAddress: Self.destination, toAmount: BigInt(1_000_000))

        XCTAssertNoThrow(try RippleHelper.getPreSignedInputData(keysignPayload: payload))
    }

    /// A duplicate nested inside a value object is refused too — the scan is
    /// structural, not a top-level key list.
    func testADuplicateCurrencyNestedInAnAmountIsRefused() {
        let rawJson = """
        {"TransactionType":"TrustSet","Account":"\(Self.account)",\
        "LimitAmount":{"currency":"USD","issuer":"\(Self.otherAddress)","value":"1000","currency":"EUR"}}
        """
        let payload = Self.makePayload(rawJson: rawJson, toAddress: "", toAmount: 0)

        XCTAssertThrowsError(
            try RippleHelper.getPreSignedInputData(keysignPayload: payload),
            "the currency walk would judge USD while the signer encodes EUR"
        )
    }

    /// …including inside an array element, which is where a future transaction
    /// type's terms would sit.
    func testADuplicateInsideAnArrayElementIsRefused() {
        let rawJson = """
        {"TransactionType":"OfferCreate","Account":"\(Self.account)","TakerGets":"5000000",\
        "Paths":[[{"currency":"USD","issuer":"\(Self.otherAddress)","currency":"EUR"}]]}
        """
        let payload = Self.makePayload(rawJson: rawJson, toAddress: "", toAmount: 0)

        XCTAssertThrowsError(try RippleHelper.getPreSignedInputData(keysignPayload: payload))
    }

    /// Two spellings of one key are one key. Both parsers compare keys DECODED,
    /// so the scan has to as well or an escaped spelling walks straight past it.
    func testAnEscapedSpellingOfADuplicateKeyIsRefused() {
        let rawJson = """
        {"TransactionType":"Payment","Account":"\(Self.account)","Destination":"\(Self.destination)",\
        "Amount":"1000000","\\u0044estination":"\(Self.otherAddress)"}
        """
        let payload = Self.makePayload(rawJson: rawJson, toAddress: Self.destination, toAmount: BigInt(1_000_000))

        XCTAssertThrowsError(
            try RippleHelper.getPreSignedInputData(keysignPayload: payload),
            "an escaped spelling of Destination is still Destination to both parsers"
        )
    }

    // MARK: - The scan does not false-reject

    /// The same key in two SIBLING objects is not a duplicate. If it were, every
    /// real issued-currency transaction would be refused — `currency` appears in
    /// both halves of an offer.
    func testTheSameKeyInSiblingObjectsIsAccepted() {
        let rawJson = """
        {"TransactionType":"OfferCreate","Account":"\(Self.account)",\
        "TakerGets":{"currency":"USD","issuer":"\(Self.otherAddress)","value":"10"},\
        "TakerPays":{"currency":"EUR","issuer":"\(Self.otherAddress)","value":"20"}}
        """
        let payload = Self.makePayload(rawJson: rawJson, toAddress: "", toAmount: 0)

        XCTAssertNoThrow(try RippleHelper.getPreSignedInputData(keysignPayload: payload))
    }

    /// Many DISTINCT keys in one object are all accepted. The field count is
    /// dApp-controlled, so the scan holds one mutable key set per open object
    /// rather than rebuilding it per key; this exercises that path in bulk as
    /// well as asserting no false rejection.
    func testAnObjectWithManyDistinctKeysIsAccepted() {
        let extras = (0..<500).map { "\"Field\($0)\":\"\($0)\"" }.joined(separator: ",")
        let rawJson = """
        {"TransactionType":"Payment","Account":"\(Self.account)","Destination":"\(Self.destination)",\
        "Amount":"1000000",\(extras)}
        """
        let payload = Self.makePayload(rawJson: rawJson, toAddress: Self.destination, toAmount: BigInt(1_000_000))

        XCTAssertNoThrow(try RippleHelper.getPreSignedInputData(keysignPayload: payload))
    }

    /// A string VALUE containing braces, colons and quoted text is text, not
    /// structure. A hex memo blob is the realistic case; this one is hostile on
    /// purpose.
    func testAStringValueThatLooksLikeJsonIsAccepted() {
        let rawJson = """
        {"TransactionType":"Payment","Account":"\(Self.account)","Destination":"\(Self.destination)",\
        "Amount":"1000000","Memos":[{"Memo":{"MemoData":"{\\"currency\\":\\"USD\\",\\"currency\\":\\"EUR\\"}"}}]}
        """
        let payload = Self.makePayload(rawJson: rawJson, toAddress: Self.destination, toAmount: BigInt(1_000_000))

        XCTAssertNoThrow(
            try RippleHelper.getPreSignedInputData(keysignPayload: payload),
            "a duplicate inside a string VALUE is text, not a repeated key"
        )
    }
}
