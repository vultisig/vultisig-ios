//
//  BitcoinPsbtSignerTests.swift
//  VultisigAppTests
//
//  Validates the BIP-143 sighash implementation against the reference
//  test vector from https://github.com/bitcoin/bips/blob/master/bip-0143.mediawiki
//  ("Native P2WPKH" example), and exercises codec round-trip via SignData.
//

@testable import VultisigApp
import VultisigCommonData
import WalletCore
import XCTest

final class BitcoinPsbtSignerTests: XCTestCase {

    // BIP-143 reference vector: native P2WPKH input #1.
    //
    // See https://github.com/bitcoin/bips/blob/master/bip-0143.mediawiki#native-p2wpkh
    // Input 0 (non-segwit, isOurs = false here so we don't sighash it),
    // input 1 (P2WPKH, value 6 BTC, scriptPubKey 0x001419 0x... -- but the
    // BIP-143 vector specifies the witness program as a 22-byte 0x00 0x14
    // pushdata over a 20-byte hash).
    //
    // The BIP says:
    //   hashPrevouts = double_sha256(...) =
    //     96b827c8483d4e9b96712b6713a7b68d6e8003a781feba36c31143470b4efd37
    //   hashSequence = double_sha256(...) =
    //     52b0a642eea2fb7ae638c36f6252b6750293dbe574a806984b8e4d8548339a3b
    //   hashOutputs = double_sha256(...) =
    //     863ef3e1a92afbfdb97f31ad0fc7683ee943e9abcf2501590ff8f6551f47e5e5
    //
    // The full signature hash for input 1 is:
    //   c37af31116d1b27caf68aae9e3ac82f1477929014d5b917657d0eb49478cb670
    func testBip143NativeP2WPKHReferenceSighash() throws {
        let inputAmount: Int64 = 600_000_000 // 6 BTC in satoshis
        let scriptPubKeyHex = "00141d0f172a0ecb48aee1be1f2687d2963ae33f71a1"
        // Coinbase-style first input (not signed, isOurs=false)
        // Input #0 sequence is 0xFFFFFFEE in the BIP-143 spec ("eeffffff" LE in the raw tx).
        // BIP-143 commits to every input's sequence in `hashSequence`, so this matters for the sighash.
        let nonOurs = BitcoinInput(
            hash: "9f96ade4b41d5433f4eda31e1738ec2b36f6e7d1420d94a6af99801a88f7f7ff",
            index: 0,
            amount: 625_000_000,
            scriptPubKey: "2103c9f4836b9a4f77fc0d81f7bcb01b7f1b35916864b9476c241ce9fc198bd25432ac",
            scriptType: "p2pk",
            sighashType: 1,
            isOurs: false,
            redeemScript: nil,
            sequence: 0xFFFFFFEE
        )
        let ours = BitcoinInput(
            hash: "8ac60eb9575db5b2d987e29f301b5b819ea83a5c6579d282d189cc04b8e151ef",
            index: 1,
            amount: inputAmount,
            scriptPubKey: scriptPubKeyHex,
            scriptType: "p2wpkh",
            sighashType: 1,
            isOurs: true,
            redeemScript: nil,
            sequence: 0xFFFFFFFF
        )
        let out0 = BitcoinOutput(
            amount: 112_340_000,
            address: "",
            opReturnData: nil,
            scriptPubKey: "76a9148280b37df378db99f66f85c95a783a76ac7a6d5988ac",
            isChange: false
        )
        let out1 = BitcoinOutput(
            amount: 223_450_000,
            address: "",
            opReturnData: nil,
            scriptPubKey: "76a9143bde42dbee7e4dbe6a21b2d50ce2f0167faa815988ac",
            isChange: false
        )
        let signBitcoin = SignBitcoin(
            version: 1,
            locktime: 17,
            inputs: [nonOurs, ours],
            outputs: [out0, out1]
        )

        let hashes = try BitcoinPsbtSigner.preSigningHashes(signBitcoin)
        XCTAssertEqual(hashes.count, 1, "Only the is_ours input should produce a sighash")
        XCTAssertEqual(
            hashes[0].hexString,
            "c37af31116d1b27caf68aae9e3ac82f1477929014d5b917657d0eb49478cb670",
            "BIP-143 native P2WPKH reference sighash mismatch"
        )
    }

    /// Quick sanity check: WalletCore's `Hash.sha256SHA256` should be the
    /// Bitcoin double-SHA256. Empty input maps to a known constant.
    func testHashSha256d() {
        let h = Hash.sha256SHA256(data: Data()).hexString
        XCTAssertEqual(h, "5df6e0e2761359d30a8275058e299fcc0381534545f55cf43e41983f5d4c9456")
    }

    /// Verify each BIP-143 intermediate value (hashPrevouts/hashSequence/hashOutputs)
    /// against the spec's reference values for the native P2WPKH vector.
    func testBip143NativeP2WPKHIntermediateHashes() {
        let nonOurs = BitcoinInput(
            hash: "9f96ade4b41d5433f4eda31e1738ec2b36f6e7d1420d94a6af99801a88f7f7ff",
            index: 0,
            amount: 625_000_000,
            scriptPubKey: "2103c9f4836b9a4f77fc0d81f7bcb01b7f1b35916864b9476c241ce9fc198bd25432ac",
            scriptType: "p2pk",
            sighashType: 1,
            isOurs: false,
            redeemScript: nil,
            sequence: 0xFFFFFFEE
        )
        let ours = BitcoinInput(
            hash: "8ac60eb9575db5b2d987e29f301b5b819ea83a5c6579d282d189cc04b8e151ef",
            index: 1,
            amount: 600_000_000,
            scriptPubKey: "00141d0f172a0ecb48aee1be1f2687d2963ae33f71a1",
            scriptType: "p2wpkh",
            sighashType: 1,
            isOurs: true,
            redeemScript: nil,
            sequence: 0xFFFFFFFF
        )
        let out0 = BitcoinOutput(
            amount: 112_340_000,
            address: "",
            opReturnData: nil,
            scriptPubKey: "76a9148280b37df378db99f66f85c95a783a76ac7a6d5988ac",
            isChange: false
        )
        let out1 = BitcoinOutput(
            amount: 223_450_000,
            address: "",
            opReturnData: nil,
            scriptPubKey: "76a9143bde42dbee7e4dbe6a21b2d50ce2f0167faa815988ac",
            isChange: false
        )
        let signBitcoin = SignBitcoin(
            version: 1,
            locktime: 17,
            inputs: [nonOurs, ours],
            outputs: [out0, out1]
        )

        XCTAssertEqual(
            BitcoinPsbtSigner._hashPrevouts(signBitcoin).hexString,
            "96b827c8483d4e9b96712b6713a7b68d6e8003a781feba36c31143470b4efd37"
        )
        XCTAssertEqual(
            BitcoinPsbtSigner._hashSequence(signBitcoin).hexString,
            "52b0a642eea2fb7ae638c36f6252b6750293dbe574a806984b8e4d8548339a3b"
        )
        XCTAssertEqual(
            try BitcoinPsbtSigner._hashOutputs(signBitcoin).hexString,
            "863ef3e1a92afbfdb97f31ad0fc7683ee943e9abcf2501590ff8f6551f47e5e5"
        )
    }

    func testInvalidOutputScriptPubKeyThrows() {
        let input = BitcoinInput(
            hash: "00".padding(toLength: 64, withPad: "0", startingAt: 0),
            index: 0,
            amount: 100_000,
            scriptPubKey: "00141d0f172a0ecb48aee1be1f2687d2963ae33f71a1",
            scriptType: "p2wpkh",
            sighashType: 1,
            isOurs: true,
            redeemScript: nil,
            sequence: 0xFFFFFFFF
        )
        let badOutput = BitcoinOutput(
            amount: 50_000,
            address: "",
            opReturnData: nil,
            scriptPubKey: "not-a-hex-string",
            isChange: false
        )
        let payload = SignBitcoin(version: 2, locktime: 0, inputs: [input], outputs: [badOutput])

        XCTAssertThrowsError(try BitcoinPsbtSigner.preSigningHashes(payload)) { err in
            guard case BitcoinPsbtSignerError.invalidOutputScriptPubKey(let i) = err else {
                XCTFail("Expected invalidOutputScriptPubKey, got \(err)")
                return
            }
            XCTAssertEqual(i, 0)
        }
    }

    func testNoOursInputsThrows() {
        let input = BitcoinInput(
            hash: "00".padding(toLength: 64, withPad: "0", startingAt: 0),
            index: 0,
            amount: 1000,
            scriptPubKey: "00141d0f172a0ecb48aee1be1f2687d2963ae33f71a1",
            scriptType: "p2wpkh",
            sighashType: 1,
            isOurs: false,
            redeemScript: nil,
            sequence: 0xFFFFFFFF
        )
        let payload = SignBitcoin(version: 2, locktime: 0, inputs: [input], outputs: [])
        XCTAssertThrowsError(try BitcoinPsbtSigner.preSigningHashes(payload)) { err in
            guard case BitcoinPsbtSignerError.noSignableInputs = err else {
                return XCTFail("Expected noSignableInputs, got \(err)")
            }
        }
    }

    func testUnsupportedScriptTypeThrows() {
        let input = BitcoinInput(
            hash: "00".padding(toLength: 64, withPad: "0", startingAt: 0),
            index: 0,
            amount: 1000,
            scriptPubKey: "5120" + String(repeating: "00", count: 32),
            scriptType: "p2tr",
            sighashType: 1,
            isOurs: true,
            redeemScript: nil,
            sequence: 0xFFFFFFFF
        )
        let payload = SignBitcoin(version: 2, locktime: 0, inputs: [input], outputs: [])
        XCTAssertThrowsError(try BitcoinPsbtSigner.preSigningHashes(payload)) { err in
            guard case BitcoinPsbtSignerError.unsupportedScriptType("p2tr") = err else {
                return XCTFail("Expected unsupportedScriptType(p2tr), got \(err)")
            }
        }
    }

    /// Round-trip a `SignData.signBitcoin` payload through the proto+JSON
    /// codable surface used by integration tests. The previous behaviour was
    /// a hard-throw on encode (see issue #4317); this confirms the new path
    /// is symmetric.
    func testSignDataSignBitcoinCodableRoundTrip() throws {
        let input = BitcoinInput(
            hash: "8ac60eb9575db5b2d987e29f301b5b819ea83a5c6579d282d189cc04b8e151ef",
            index: 1,
            amount: 600_000_000,
            scriptPubKey: "00141d0f172a0ecb48aee1be1f2687d2963ae33f71a1",
            scriptType: "p2wpkh",
            sighashType: 1,
            isOurs: true,
            redeemScript: nil,
            sequence: 0xFFFFFFFF
        )
        let output = BitcoinOutput(
            amount: 590_000_000,
            address: "bc1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3qccfmv3",
            opReturnData: nil,
            scriptPubKey: "0020c7a1f1a4d6b4c1802a59631966a18359de779e8a6a65973735a3ccdfdabc407d",
            isChange: false
        )
        let original = SignData.signBitcoin(SignBitcoin(
            version: 2,
            locktime: 0,
            inputs: [input],
            outputs: [output]
        ))

        // Encode and decode through the proto-backed Codable surface (same
        // path the relay uses for keysign payload transport in tests).
        let proto = original.mapToProtobuff()
        let encoded = try JSONEncoder().encode(proto)
        let decodedProto = try JSONDecoder().decode(VSKeysignPayload.OneOf_SignData.self, from: encoded)
        guard let decoded = SignData(proto: decodedProto) else {
            return XCTFail("Failed to decode signBitcoin SignData")
        }
        XCTAssertEqual(decoded, original)
    }
}
