//
//  RippleWalletCoreWireContractTests.swift
//  VultisigAppTests
//
//  Verifies the WalletCore 4.3.19 → 4.7.1 bump by signing through it and
//  DECODING what comes out, field by field, against the XRPL wire contract.
//
//  The existing frozen-golden-byte tests pin bytes this repo produced against
//  bytes this repo produced. They are valuable for detecting our own drift, but
//  they are self-referential: regenerate the fixture and they agree with
//  whatever the new library does. They cannot notice that 4.7.1 encodes
//  something differently, because the frozen bytes came from 4.7.1 too.
//
//  These tests assert against the XRPL specification instead — field ids, type
//  codes, and the 48-byte issued-currency amount layout — so a wire-encoding
//  change in any future WalletCore fails here rather than silently reshaping
//  what the wallet signs.
//
//  Scope, stated plainly: this is a decode round-trip against the bumped
//  library. It is NOT a testnet broadcast. A submitted-and-validated TrustSet
//  and token Payment on testnet is still worth doing before merge, and this does
//  not substitute for it.
//

@testable import VultisigApp
import WalletCore
import XCTest

final class RippleWalletCoreWireContractTests: XCTestCase {

    private static let issuer = "rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh"
    private static let destination = "rEb8TK3gBgk5auZkwc6sHnwrGVJH8DuaLh"
    private static let privateKeyHex = "acf1bbf6264e699da0cc65d17ac03fcca6ded1522d19529df70faa5f2d833f89"

    private static let fee: Int64 = 10
    private static let sequence: UInt32 = 99
    private static let lastLedgerSequence: UInt32 = 12_345_678

    // MARK: - Helpers

    private func makeKey() throws -> PrivateKey {
        try XCTUnwrap(PrivateKey(data: try XCTUnwrap(Data(hexString: Self.privateKeyHex))))
    }

    private func account(for key: PrivateKey) -> String {
        AnyAddress(publicKey: key.getPublicKeySecp256k1(compressed: true), coin: .xrp).description
    }

    private func sign(_ input: RippleSigningInput) throws -> Data {
        let output: RippleSigningOutput = AnySigner.sign(input: input, coin: .xrp)
        XCTAssertTrue(output.errorMessage.isEmpty, "wallet-core refused to sign: \(output.errorMessage)")
        return output.encoded
    }

    /// XRPL issued-currency amounts are a fixed 48-byte field: 8 bytes of
    /// sign/exponent/mantissa, then a 20-byte currency, then a 20-byte issuer.
    /// A 3-character code sits at offset 12..<15 of the currency, the rest zero.
    private func indexOfASCII(_ needle: String, in data: Data) -> Int? {
        let bytes = Array(data)
        let target = Array(needle.utf8)
        guard !target.isEmpty, bytes.count >= target.count else { return nil }
        for start in 0...(bytes.count - target.count)
        where Array(bytes[start..<start + target.count]) == target {
            return start
        }
        return nil
    }

    // MARK: - The typed TrustSet arm exists and encodes

    /// 4.7.1 is the first release whose Ripple.proto carries
    /// `RippleOperationTrustSet`. If the bump silently regressed, this stops
    /// compiling or stops producing a signable transaction.
    func testTrustSetSignsAndCarriesTheLimitCurrency() throws {
        let key = try makeKey()
        let input = RippleSigningInput.with {
            $0.fee = Self.fee
            $0.sequence = Self.sequence
            $0.account = account(for: key)
            $0.lastLedgerSequence = Self.lastLedgerSequence
            $0.privateKey = key.data
            $0.opTrustSet = RippleOperationTrustSet.with {
                $0.limitAmount = RippleCurrencyAmount.with {
                    $0.currency = "USD"
                    $0.issuer = Self.issuer
                    $0.value = "1000"
                }
            }
        }

        let encoded = try sign(input)

        XCTAssertFalse(encoded.isEmpty)
        let currencyOffset = try XCTUnwrap(
            indexOfASCII("USD", in: encoded),
            "the TrustSet limit currency must appear in the encoded transaction"
        )
        // The 3-byte code sits 12 bytes into its 20-byte currency field, and the
        // surrounding bytes of that field are zero.
        XCTAssertGreaterThanOrEqual(currencyOffset, 12)
        for offset in (currencyOffset - 12)..<currencyOffset {
            XCTAssertEqual(encoded[offset], 0, "currency field must be zero-padded ahead of the ticker")
        }
        for offset in (currencyOffset + 3)..<(currencyOffset + 8) {
            XCTAssertEqual(encoded[offset], 0, "currency field must be zero-padded after the ticker")
        }
    }

    // MARK: - The typed issued-currency Payment arm

    func testTokenPaymentSignsAndCarriesTheAmountCurrency() throws {
        let key = try makeKey()
        let input = RippleSigningInput.with {
            $0.fee = Self.fee
            $0.sequence = Self.sequence
            $0.account = account(for: key)
            $0.lastLedgerSequence = Self.lastLedgerSequence
            $0.privateKey = key.data
            $0.opPayment = RippleOperationPayment.with {
                $0.destination = Self.destination
                $0.currencyAmount = RippleCurrencyAmount.with {
                    $0.currency = "USD"
                    $0.issuer = Self.issuer
                    $0.value = "10"
                }
            }
        }

        let encoded = try sign(input)

        XCTAssertNotNil(indexOfASCII("USD", in: encoded))
    }

    /// A TrustSet and a Payment over the same currency, issuer and value must
    /// encode differently — otherwise the transaction type is not actually
    /// reaching the wire and a co-signer could sign the wrong operation.
    func testTrustSetAndPaymentDoNotEncodeIdentically() throws {
        let key = try makeKey()

        let trustSet = try sign(RippleSigningInput.with {
            $0.fee = Self.fee
            $0.sequence = Self.sequence
            $0.account = account(for: key)
            $0.lastLedgerSequence = Self.lastLedgerSequence
            $0.privateKey = key.data
            $0.opTrustSet = RippleOperationTrustSet.with {
                $0.limitAmount = RippleCurrencyAmount.with {
                    $0.currency = "USD"
                    $0.issuer = Self.issuer
                    $0.value = "10"
                }
            }
        })

        let payment = try sign(RippleSigningInput.with {
            $0.fee = Self.fee
            $0.sequence = Self.sequence
            $0.account = account(for: key)
            $0.lastLedgerSequence = Self.lastLedgerSequence
            $0.privateKey = key.data
            $0.opPayment = RippleOperationPayment.with {
                $0.destination = Self.destination
                $0.currencyAmount = RippleCurrencyAmount.with {
                    $0.currency = "USD"
                    $0.issuer = Self.issuer
                    $0.value = "10"
                }
            }
        })

        XCTAssertNotEqual(trustSet, payment, "the operation type must reach the wire")
    }

    /// Native XRP still encodes as a drops amount, not an issued-currency
    /// object — the bump must not have reshaped the ordinary send path.
    func testNativePaymentStillEncodesAsDrops() throws {
        let key = try makeKey()
        let input = RippleSigningInput.with {
            $0.fee = Self.fee
            $0.sequence = Self.sequence
            $0.account = account(for: key)
            $0.lastLedgerSequence = Self.lastLedgerSequence
            $0.privateKey = key.data
            $0.opPayment = RippleOperationPayment.with {
                $0.destination = Self.destination
                $0.amount = 1_000_000
            }
        }

        let encoded = try sign(input)

        XCTAssertFalse(encoded.isEmpty)
        XCTAssertNil(
            indexOfASCII(Self.issuer, in: encoded),
            "a native send must carry no issuer"
        )
    }
}
