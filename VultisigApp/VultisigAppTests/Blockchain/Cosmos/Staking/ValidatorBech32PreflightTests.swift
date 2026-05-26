//
//  ValidatorBech32PreflightTests.swift
//  VultisigAppTests
//
//  Mirrors the agent-app `requireValoper(...)` guard at
//  `vultiagent-app/src/services/cosmosTx.ts:1110-1140`. Every test case
//  exists to fail loud before the MPC ceremony spends a signing round on
//  a tx the chain will reject.
//

@testable import VultisigApp
import XCTest

final class ValidatorBech32PreflightTests: XCTestCase {

    // MARK: - Empty / structural

    func testEmptyAddressIsRejected() {
        XCTAssertThrowsError(try ValidatorBech32Preflight.validate("", for: .terra)) { error in
            XCTAssertEqual(error as? ValidatorBech32Preflight.ValidatorBech32Error, .empty)
        }
    }

    func testGarbageStringIsRejected() {
        XCTAssertThrowsError(try ValidatorBech32Preflight.validate("not bech32 at all!!", for: .terra)) { error in
            XCTAssertEqual(error as? ValidatorBech32Preflight.ValidatorBech32Error, .badEncoding)
        }
    }

    func testStringWithoutSeparatorIsRejected() {
        XCTAssertThrowsError(try ValidatorBech32Preflight.validate("terravaloperabcdefghij", for: .terra))
    }

    func testMixedCaseAddressIsRejected() {
        // BIP-173 forbids mixed case. A Terra address pasted from a
        // misformatted email signature must not slip through.
        let mixed = makeValidValoperAddress().uppercasedFirstHalf()
        XCTAssertThrowsError(try ValidatorBech32Preflight.validate(mixed, for: .terra))
    }

    // MARK: - Prefix

    func testWrongPrefixIsRejectedForTerra() {
        // `terra1…` is a delegator account address; `terravaloper1…` is the
        // operator address. The valoper form is what x/staking expects;
        // accidentally using the account form would burn an MPC ceremony.
        let address = makeAddress(hrp: "terra", payloadLength: 20)
        XCTAssertThrowsError(try ValidatorBech32Preflight.validate(address, for: .terra)) { error in
            guard case .wrongPrefix(let actual, let expected) =
                    error as? ValidatorBech32Preflight.ValidatorBech32Error else {
                XCTFail("Expected wrongPrefix, got \(error)")
                return
            }
            XCTAssertEqual(actual, "terra")
            XCTAssertEqual(expected, "terravaloper")
        }
    }

    func testCosmoshubValoperRejectedOnTerraChain() {
        // Cosmoshub valoper would pass a generic "cosmos" prefix check —
        // the per-chain HRP guard is the only thing that catches it.
        let address = makeAddress(hrp: "cosmosvaloper", payloadLength: 20)
        XCTAssertThrowsError(try ValidatorBech32Preflight.validate(address, for: .terra)) { error in
            guard case .wrongPrefix(let actual, let expected) =
                    error as? ValidatorBech32Preflight.ValidatorBech32Error else {
                XCTFail("Expected wrongPrefix, got \(error)")
                return
            }
            XCTAssertEqual(actual, "cosmosvaloper")
            XCTAssertEqual(expected, "terravaloper")
        }
    }

    // MARK: - Payload length

    func testThirtyTwoByteConsensusPayloadIsRejected() {
        // *valconspub1… consensus pubkeys are 32 bytes wrapped in the same
        // bech32 envelope. The HRP differs in production, but a malicious
        // submitter could spoof the valoper HRP — the payload-length guard
        // catches that.
        let address = makeAddress(hrp: "terravaloper", payloadLength: 32)
        XCTAssertThrowsError(try ValidatorBech32Preflight.validate(address, for: .terra)) { error in
            guard case .wrongPayloadLength(let actual, let expected) =
                    error as? ValidatorBech32Preflight.ValidatorBech32Error else {
                XCTFail("Expected wrongPayloadLength, got \(error)")
                return
            }
            XCTAssertEqual(actual, 32)
            XCTAssertEqual(expected, 20)
        }
    }

    // MARK: - Happy path

    func testValid20ByteTerraValoperPasses() throws {
        let address = makeAddress(hrp: "terravaloper", payloadLength: 20)
        XCTAssertNoThrow(try ValidatorBech32Preflight.validate(address, for: .terra))
    }

    func testValid20ByteTerraValoperAlsoPassesOnTerraClassic() throws {
        // LUNC shares the `terravaloper` HRP with LUNA — both chains pass
        // the same address.
        let address = makeAddress(hrp: "terravaloper", payloadLength: 20)
        XCTAssertNoThrow(try ValidatorBech32Preflight.validate(address, for: .terraClassic))
    }

    // MARK: - Decode primitive (covers the bech32 routine itself)

    func testRoundTripDecodeProducesOriginalHrpAndPayload() throws {
        let payload = Data((0..<20).map { _ in UInt8.random(in: 0...255) })
        let address = encodeBech32(hrp: "terravaloper", payload: Array(payload))
        let decoded = try ValidatorBech32Preflight.decode(address)
        XCTAssertEqual(decoded.hrp, "terravaloper")
        XCTAssertEqual(decoded.payload, Array(payload))
    }

    func testFlippedChecksumByteIsRejected() {
        // The last char of a valid bech32 address is part of the checksum.
        // Flipping it must be rejected.
        var address = makeAddress(hrp: "terravaloper", payloadLength: 20)
        let charBefore = address.removeLast()
        // Pick the next charset symbol — guaranteed to change the checksum.
        let charset = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
        let oldIndex = charset.firstIndex(of: charBefore) ?? 0
        let nextIndex = (oldIndex + 1) % charset.count
        address.append(charset[nextIndex])
        XCTAssertThrowsError(try ValidatorBech32Preflight.validate(address, for: .terra))
    }

    // MARK: - Helpers

    private func makeValidValoperAddress() -> String {
        makeAddress(hrp: "terravaloper", payloadLength: 20)
    }

    private func makeAddress(hrp: String, payloadLength: Int) -> String {
        // Deterministic payload so tests are reproducible.
        let payload = (0..<payloadLength).map { UInt8($0 & 0xff) }
        return encodeBech32(hrp: hrp, payload: payload)
    }

    /// Test-only bech32 encoder used to assemble inputs. The production
    /// code only ever decodes, so this round-trip helper lives in the test
    /// target — keeps the prod surface narrower.
    private func encodeBech32(hrp: String, payload: [UInt8]) -> String {
        let charset = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
        let data5Bit = convertBits(payload, from: 8, to: 5, pad: true)
        let checksum = createChecksum(hrp: hrp, data: data5Bit)
        let combined = data5Bit + checksum
        return hrp + "1" + String(combined.map { charset[Int($0)] })
    }

    private func convertBits(_ data: [UInt8], from fromBits: Int, to toBits: Int, pad: Bool) -> [UInt8] {
        var acc = 0
        var bits = 0
        var result: [UInt8] = []
        let maxv = (1 << toBits) - 1
        for value in data {
            acc = (acc << fromBits) | Int(value)
            bits += fromBits
            while bits >= toBits {
                bits -= toBits
                result.append(UInt8((acc >> bits) & maxv))
            }
        }
        if pad && bits > 0 {
            result.append(UInt8((acc << (toBits - bits)) & maxv))
        }
        return result
    }

    private func createChecksum(hrp: String, data: [UInt8]) -> [UInt8] {
        let values = hrpExpand(hrp) + data + Array(repeating: UInt8(0), count: 6)
        let mod = polymod(values) ^ 1
        return (0..<6).map { UInt8((mod >> (5 * (5 - $0))) & 0x1f) }
    }

    private func hrpExpand(_ hrp: String) -> [UInt8] {
        let bytes = Array(hrp.utf8)
        var out: [UInt8] = bytes.map { $0 >> 5 }
        out.append(0)
        out.append(contentsOf: bytes.map { $0 & 0x1f })
        return out
    }

    private func polymod(_ values: [UInt8]) -> UInt32 {
        let generator: [UInt32] = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]
        var chk: UInt32 = 1
        for value in values {
            let top = chk >> 25
            chk = ((chk & 0x1ffffff) << 5) ^ UInt32(value)
            for index in 0..<5 where ((top >> index) & 1) == 1 {
                chk ^= generator[index]
            }
        }
        return chk
    }
}

// MARK: - String mixed-case helper

private extension String {
    /// Uppercases roughly the first half of the string — used to assemble
    /// a mixed-case bech32 input for the BIP-173 mixed-case rejection test.
    func uppercasedFirstHalf() -> String {
        let mid = index(startIndex, offsetBy: count / 2)
        return self[startIndex..<mid].uppercased() + self[mid...]
    }
}
