//
//  RippleCurrencyCodeCaseTests.swift
//  VultisigAppTests
//
//  Pins what wallet-core actually does with the case of a 3-byte issued-currency
//  code, on BOTH signing paths.
//
//  `bindPaymentToReviewedValues` refuses a dApp Payment whose currency code is
//  not already uppercase, on the stated grounds that wallet-core uppercases a
//  3-byte code before encoding — so agreeing on `usd` would still put `USD` on
//  the ledger, a currency neither the dApp nor the reviewer named. That gate is
//  only justified if the claim is true, and it was inferred from the typed
//  (`currencyAmount`) path rather than measured on the rawJson path the gate
//  actually guards.
//
//  These tests measure it. They sign through wallet-core and read the ASCII back
//  out of the encoded transaction, because the encoded bytes are the only thing
//  that settles what reaches the ledger — the typed path's behaviour is not
//  evidence for the rawJson path's.
//
//  XRPL wire format: a 3-character currency occupies bytes 12..<15 of a 20-byte
//  currency field, the rest zero. So the ticker appears verbatim as ASCII inside
//  the encoded blob, and searching for it is exact rather than heuristic.
//

@testable import VultisigApp
import WalletCore
import XCTest

final class RippleCurrencyCodeCaseTests: XCTestCase {

    /// Derived from the signing key rather than hardcoded: wallet-core rejects
    /// an input whose `account` does not belong to the key it is signing with.
    private static func derivedAccount(for key: PrivateKey) -> String {
        AnyAddress(publicKey: key.getPublicKeySecp256k1(compressed: true), coin: .xrp).description
    }
    private static let destination = "rEb8TK3gBgk5auZkwc6sHnwrGVJH8DuaLh"
    private static let issuer = "rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh"

    /// Any valid secp256k1 key works — the signature is irrelevant here, only
    /// the encoded transaction body is.
    private static let privateKeyHex = "acf1bbf6264e699da0cc65d17ac03fcca6ded1522d19529df70faa5f2d833f89"

    private static let sequence: UInt32 = 99
    private static let fee: Int64 = 10
    private static let lastLedgerSequence: UInt32 = 12_345_678

    // MARK: - Helpers

    private func makePrivateKey() throws -> PrivateKey {
        let data = try XCTUnwrap(Data(hexString: Self.privateKeyHex))
        return try XCTUnwrap(PrivateKey(data: data))
    }

    /// Signs and returns the encoded transaction bytes.
    private func encodedTransaction(from input: RippleSigningInput) throws -> Data {
        let output: RippleSigningOutput = AnySigner.sign(input: input, coin: .xrp)
        XCTAssertTrue(output.errorMessage.isEmpty, "wallet-core refused to sign: \(output.errorMessage)")
        XCTAssertFalse(output.encoded.isEmpty, "wallet-core produced no encoded transaction")
        return output.encoded
    }

    /// Whether the encoded transaction contains this exact ASCII run.
    ///
    /// Case-sensitive and byte-exact by design: the entire question is whether
    /// the case survived.
    private func encoded(_ data: Data, containsASCII needle: String) -> Bool {
        let bytes = Array(data)
        let target = Array(needle.utf8)
        guard !target.isEmpty, bytes.count >= target.count else { return false }
        for start in 0...(bytes.count - target.count) where Array(bytes[start..<start + target.count]) == target {
            return true
        }
        return false
    }

    private func rawJsonPayment(currency: String, account: String) -> String {
        """
        {
          "TransactionType": "Payment",
          "Account": "\(account)",
          "Destination": "\(Self.destination)",
          "Amount": {
            "currency": "\(currency)",
            "issuer": "\(Self.issuer)",
            "value": "1"
          }
        }
        """
    }

    private func rawJsonInput(currency: String) throws -> RippleSigningInput {
        let key = try makePrivateKey()
        return RippleSigningInput.with {
            $0.fee = Self.fee
            $0.sequence = Self.sequence
            $0.account = Self.derivedAccount(for: key)
            $0.lastLedgerSequence = Self.lastLedgerSequence
            $0.privateKey = key.data
            $0.rawJson = rawJsonPayment(currency: currency, account: Self.derivedAccount(for: key))
        }
    }

    private func typedInput(currency: String) throws -> RippleSigningInput {
        let key = try makePrivateKey()
        return RippleSigningInput.with {
            $0.fee = Self.fee
            $0.sequence = Self.sequence
            $0.account = Self.derivedAccount(for: key)
            $0.lastLedgerSequence = Self.lastLedgerSequence
            $0.privateKey = key.data
            $0.opPayment = RippleOperationPayment.with {
                $0.destination = Self.destination
                $0.currencyAmount = RippleCurrencyAmount.with {
                    $0.currency = currency
                    $0.issuer = Self.issuer
                    $0.value = "1"
                }
            }
        }
    }

    // MARK: - Control: an already-uppercase code survives verbatim

    func testUppercaseCurrencySurvivesTheRawJsonPath() throws {
        let encoded = try encodedTransaction(from: try rawJsonInput(currency: "USD"))

        XCTAssertTrue(
            self.encoded(encoded, containsASCII: "USD"),
            "An uppercase code must reach the ledger unchanged"
        )
    }

    func testUppercaseCurrencySurvivesTheTypedPath() throws {
        let encoded = try encodedTransaction(from: try typedInput(currency: "USD"))

        XCTAssertTrue(self.encoded(encoded, containsASCII: "USD"))
    }

    // MARK: - The question the gate depends on

    //  Proved by byte equality of the WHOLE encoded transaction rather than by
    //  searching it for `USD`. A substring search is heuristic — three ASCII
    //  bytes can occur coincidentally in a signature — and this measurement is
    //  the evidence the signing gate rests on, so it has to be exact.
    //
    //  Two inputs differing ONLY in the case of the currency code: if wallet-core
    //  uppercases, both encode to identical bytes. Nothing else can make two
    //  different inputs agree byte for byte.

    func testLowercaseCurrencyEncodesIdenticallyToUppercaseOnTheRawJsonPath() throws {
        let lower = try encodedTransaction(from: try rawJsonInput(currency: "usd"))
        let upper = try encodedTransaction(from: try rawJsonInput(currency: "USD"))

        XCTAssertEqual(
            lower, upper,
            "`usd` and `USD` encode identically — wallet-core uppercases 3-byte codes on the rawJson path"
        )
    }

    func testMixedCaseCurrencyEncodesIdenticallyToUppercaseOnTheRawJsonPath() throws {
        let mixed = try encodedTransaction(from: try rawJsonInput(currency: "UsD"))
        let upper = try encodedTransaction(from: try rawJsonInput(currency: "USD"))

        XCTAssertEqual(mixed, upper)
    }

    func testLowercaseCurrencyEncodesIdenticallyToUppercaseOnTheTypedPath() throws {
        let lower = try encodedTransaction(from: try typedInput(currency: "usd"))
        let upper = try encodedTransaction(from: try typedInput(currency: "USD"))

        XCTAssertEqual(lower, upper)
    }

    /// Control for the equality argument: the comparison must be sensitive to
    /// the currency at all, or "identical bytes" would prove nothing.
    func testDifferentCurrenciesDoNotEncodeIdentically() throws {
        let usd = try encodedTransaction(from: try rawJsonInput(currency: "USD"))
        let eur = try encodedTransaction(from: try rawJsonInput(currency: "EUR"))

        XCTAssertNotEqual(usd, eur, "the encoding must depend on the currency code")
    }

    /// Supplementary, not the proof: the uppercase ticker is present in the
    /// blob and the lowercase one is absent. Consistent with the equality
    /// result above, which is what actually settles it.
    func testUppercaseTickerAppearsAndLowercaseDoesNot() throws {
        let encoded = try encodedTransaction(from: try rawJsonInput(currency: "usd"))

        XCTAssertTrue(self.encoded(encoded, containsASCII: "USD"))
        XCTAssertFalse(self.encoded(encoded, containsASCII: "usd"))
    }

    // MARK: - The gate agrees with the measurement

    /// Whatever wallet-core does, `isSignableCurrencyCode` must refuse exactly
    /// the codes it would mangle and accept exactly the ones it preserves.
    func testTheGateRefusesPreciselyWhatWalletCoreWouldMangle() throws {
        for currency in ["usd", "UsD", "uSd"] {
            XCTAssertFalse(
                RippleIssuedCurrency.isSignableCurrencyCode(currency),
                "\(currency) is mangled by wallet-core and must be refused"
            )
        }
        XCTAssertTrue(RippleIssuedCurrency.isSignableCurrencyCode("USD"))
    }

    // MARK: - wallet-core classifies by RAW BYTE LENGTH, not by trimmed characters

    //  `toXrplCurrencyCode` trims whitespace and then ASCII-packs anything that
    //  is neither 3 characters nor 40 hex digits. wallet-core does neither: it
    //  reads the raw string and treats exactly 3 BYTES as an ISO code.
    //
    //  That gap is what the rawJson gate has to be built on, so it is measured
    //  here rather than reasoned about. Every assertion below compares WHOLE
    //  encoded transactions for the reason stated above: two inputs differing
    //  only in the currency can agree byte for byte only if wallet-core resolved
    //  them to the same currency.

    private static let hexRlusd = "524C555344000000000000000000000000000000"

    /// A 3-BYTE code with edge whitespace is an ISO code to wallet-core, and its
    /// lowercase byte is uppercased like any other — `Ab ` is signed as `AB `.
    func testAWhitespaceEdgedThreeByteCodeIsUppercasedAsAnIsoCode() throws {
        let edged = try encodedTransaction(from: try rawJsonInput(currency: "Ab "))
        let upper = try encodedTransaction(from: try rawJsonInput(currency: "AB "))

        XCTAssertEqual(
            edged, upper,
            "wallet-core reads 3 raw bytes as an ISO code and uppercases them, whitespace included"
        )
    }

    /// …and what it signs is NOT the ASCII-packed hex of the trimmed ticker,
    /// which is what `toXrplCurrencyCode` makes of the same string. Normalising
    /// before classifying therefore judges a currency that never reaches the
    /// ledger.
    func testAWhitespaceEdgedThreeByteCodeIsNotThePackedHexOfItsTrimmedForm() throws {
        let edged = try encodedTransaction(from: try rawJsonInput(currency: "Ab "))
        let packed = try encodedTransaction(
            from: try rawJsonInput(currency: try RippleIssuedCurrency.toXrplCurrencyCode("Ab "))
        )

        XCTAssertNotEqual(
            edged, packed,
            "the normalised form is a different currency than the one wallet-core signs"
        )
    }

    /// The split is not about whitespace. A single 3-BYTE character diverges the
    /// same way, because wallet-core classifies on byte length while
    /// normalisation classifies on character count and then packs to hex.
    ///
    /// Stated precisely: this proves the two forms are DIFFERENT currencies, not
    /// that wallet-core specifically took the ISO branch. Divergence is the whole
    /// property the gate needs — a code the two classify differently must be
    /// refused whichever branch produced it.
    func testAThreeByteNonAsciiCodeIsNotThePackedHexOfItsNormalisedForm() throws {
        let euro = try encodedTransaction(from: try rawJsonInput(currency: "\u{20AC}"))
        let packed = try encodedTransaction(
            from: try rawJsonInput(currency: try RippleIssuedCurrency.toXrplCurrencyCode("\u{20AC}"))
        )

        XCTAssertNotEqual(euro, packed, "a 1-character, 3-byte code splits the two classifications too")
    }

    /// A 40-character hex code is decoded case-insensitively, so accepting
    /// either spelling verbatim mangles nothing. This is what licenses the
    /// verbatim gate not requiring uppercase hex.
    func testHexCurrencyCodeIsCaseInsensitive() throws {
        let upper = try encodedTransaction(from: try rawJsonInput(currency: Self.hexRlusd))
        let lower = try encodedTransaction(from: try rawJsonInput(currency: Self.hexRlusd.lowercased()))

        XCTAssertEqual(upper, lower, "hex is decoded case-insensitively, so either spelling is verbatim")
    }

    /// A length wallet-core cannot classify is refused by wallet-core itself, so
    /// the gate refusing it costs nothing: `RLUSD` was never signable, it was
    /// only ASCII-packed by the old gate into a code the signer never received.
    func testACodeThatIsNeitherThreeBytesNorFortyHexIsRefusedByWalletCore() throws {
        for currency in ["RLUSD", "Ab"] {
            let output: RippleSigningOutput = AnySigner.sign(input: try rawJsonInput(currency: currency), coin: .xrp)
            XCTAssertFalse(
                output.errorMessage.isEmpty,
                "wallet-core must refuse '\(currency)' outright rather than pack it"
            )
            XCTAssertTrue(
                output.encoded.isEmpty,
                "a refused input must produce no transaction at all: '\(currency)'"
            )
        }
    }

    /// The verbatim gate's verdicts, each justified by one of the measurements
    /// above (or by rippled's own standard-code repertoire).
    func testTheVerbatimGateAgreesWithTheMeasurements() {
        XCTAssertTrue(RippleIssuedCurrency.isVerbatimSignableCurrencyCode("USD"), "signed verbatim")
        XCTAssertTrue(RippleIssuedCurrency.isVerbatimSignableCurrencyCode(Self.hexRlusd), "signed verbatim")
        XCTAssertTrue(
            RippleIssuedCurrency.isVerbatimSignableCurrencyCode(Self.hexRlusd.lowercased()),
            "hex is decoded case-insensitively, so this is the same 20 bytes"
        )

        XCTAssertFalse(RippleIssuedCurrency.isVerbatimSignableCurrencyCode("usd"), "uppercased by the signer")
        XCTAssertFalse(RippleIssuedCurrency.isVerbatimSignableCurrencyCode("Ab "), "uppercased by the signer")
        XCTAssertFalse(
            RippleIssuedCurrency.isVerbatimSignableCurrencyCode("AB "),
            "signed unchanged, but a space is outside rippled's standard-code repertoire"
        )
        XCTAssertFalse(
            RippleIssuedCurrency.isVerbatimSignableCurrencyCode(" AB"),
            "signed unchanged, but a space is outside rippled's standard-code repertoire"
        )
        XCTAssertFalse(RippleIssuedCurrency.isVerbatimSignableCurrencyCode("\u{20AC}"), "outside the repertoire")
        XCTAssertFalse(RippleIssuedCurrency.isVerbatimSignableCurrencyCode("RLUSD"), "wallet-core refuses it outright")
        XCTAssertFalse(RippleIssuedCurrency.isVerbatimSignableCurrencyCode("Ab"), "wallet-core refuses it outright")
        XCTAssertFalse(RippleIssuedCurrency.isVerbatimSignableCurrencyCode(""), "not a currency")
    }
}
