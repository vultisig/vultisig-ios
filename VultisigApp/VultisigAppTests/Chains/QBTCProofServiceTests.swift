//
//  QBTCProofServiceTests.swift
//  VultisigAppTests
//
//  Wire-format parity tests for the QBTC proof service client.
//  Mirrors vultisig-sdk/.../proofService.ts: confirms JSON keys are
//  snake_case (the prover doesn't accept camelCase) and that signature
//  padding hits exactly 24/32 bytes.
//

@testable import VultisigApp
import XCTest

final class QBTCProofServiceTests: XCTestCase {
    // MARK: - padSigHex

    func testPadSigHexPadsShortInput() {
        // r is 24 bytes → 48 hex chars
        let padded = ClaimProofRequest.padSigHex("abcd", byteLength: QBTCClaimConfig.proofServiceRBytes)
        XCTAssertEqual(padded, "0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000abcd".suffix(48).description)
        XCTAssertEqual(padded.count, 48)
    }

    func testPadSigHexLeavesExactWidthUnchanged() {
        let exact = String(repeating: "ab", count: 24)
        let padded = ClaimProofRequest.padSigHex(exact, byteLength: QBTCClaimConfig.proofServiceRBytes)
        XCTAssertEqual(padded, exact)
        XCTAssertEqual(padded.count, 48)
    }

    func testPadSigHexProduces32BytesForS() {
        // s is 32 bytes → 64 hex chars
        let padded = ClaimProofRequest.padSigHex("ff", byteLength: QBTCClaimConfig.proofServiceSBytes)
        XCTAssertEqual(padded.count, 64)
        XCTAssertTrue(padded.hasSuffix("ff"))
        XCTAssertTrue(padded.hasPrefix(String(repeating: "0", count: 62)))
    }

    func testPadSigHexZeroInputBecomesAllZeros() {
        let padded = ClaimProofRequest.padSigHex("", byteLength: QBTCClaimConfig.proofServiceRBytes)
        XCTAssertEqual(padded, String(repeating: "0", count: 48))
    }

    // MARK: - ClaimProofRequest convenience init

    func testRequestInitPadsBothSignatureComponents() {
        let request = ClaimProofRequest(
            rHex: "deadbeef",
            sHex: "cafebabe",
            compressedPubkeyHex: String(repeating: "02", count: 33),
            utxos: [ClaimableUtxo(txid: String(repeating: "aa", count: 32), vout: 0, amount: 100)],
            claimerAddress: "qbtc1abc",
            chainId: QBTCClaimConfig.chainId
        )

        // r → 24 bytes (48 hex chars), zero-padded on left
        XCTAssertEqual(request.signatureR.count, 48)
        XCTAssertTrue(request.signatureR.hasSuffix("deadbeef"))
        XCTAssertTrue(request.signatureR.hasPrefix(String(repeating: "0", count: 40)))

        // s → 32 bytes (64 hex chars), zero-padded on left
        XCTAssertEqual(request.signatureS.count, 64)
        XCTAssertTrue(request.signatureS.hasSuffix("cafebabe"))
        XCTAssertTrue(request.signatureS.hasPrefix(String(repeating: "0", count: 56)))
    }

    func testRequestInitMapsClaimableUtxosToProofUtxoRefs() {
        let utxos = [
            ClaimableUtxo(txid: String(repeating: "aa", count: 32), vout: 0, amount: 1),
            ClaimableUtxo(txid: String(repeating: "bb", count: 32), vout: 7, amount: 2)
        ]
        let request = ClaimProofRequest(
            rHex: "01", sHex: "02",
            compressedPubkeyHex: "03",
            utxos: utxos,
            claimerAddress: "qbtc1abc",
            chainId: QBTCClaimConfig.chainId
        )

        XCTAssertEqual(request.utxos.count, 2)
        XCTAssertEqual(request.utxos[0].txid, utxos[0].txid)
        XCTAssertEqual(request.utxos[0].vout, 0)
        XCTAssertEqual(request.utxos[1].txid, utxos[1].txid)
        XCTAssertEqual(request.utxos[1].vout, 7)
    }

    // MARK: - JSON encoding (snake_case parity with the prover)

    func testRequestEncodesUsingSnakeCaseKeys() throws {
        let request = ClaimProofRequest(
            rHex: "01", sHex: "02",
            compressedPubkeyHex: "03",
            utxos: [ClaimableUtxo(txid: String(repeating: "aa", count: 32), vout: 5, amount: 10)],
            claimerAddress: "qbtc1abc",
            chainId: QBTCClaimConfig.chainId
        )
        let data = try JSONEncoder().encode(request)
        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        // Top-level keys MUST be snake_case — the prover does not accept camelCase.
        XCTAssertEqual(Set(dict.keys), [
            "signature_r", "signature_s", "public_key",
            "utxos", "claimer_address", "chain_id"
        ])

        // utxos[0] keys: txid + vout (no `amount` from ClaimableUtxo).
        let utxos = try XCTUnwrap(dict["utxos"] as? [[String: Any]])
        XCTAssertEqual(utxos.count, 1)
        XCTAssertEqual(Set(utxos[0].keys), ["txid", "vout"])

        XCTAssertEqual(dict["chain_id"] as? String, QBTCClaimConfig.chainId)
        XCTAssertEqual(dict["claimer_address"] as? String, "qbtc1abc")
    }

    // MARK: - JSON decoding

    func testResponseDecodesFromSnakeCaseJSON() throws {
        let json = """
        {
          "proof": "ff00",
          "message_hash": "\(String(repeating: "bb", count: 32))",
          "address_hash": "\(String(repeating: "cc", count: 20))",
          "qbtc_address_hash": "\(String(repeating: "dd", count: 32))",
          "utxos": [{"txid": "\(String(repeating: "aa", count: 32))", "vout": 3}],
          "claimer_address": "qbtc1abc"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(ClaimProofResponse.self, from: json)
        XCTAssertEqual(decoded.proof, "ff00")
        XCTAssertEqual(decoded.messageHash.count, 64)
        XCTAssertEqual(decoded.addressHash.count, 40)
        XCTAssertEqual(decoded.qbtcAddressHash.count, 64)
        XCTAssertEqual(decoded.utxos.count, 1)
        XCTAssertEqual(decoded.utxos[0].vout, 3)
        XCTAssertEqual(decoded.claimerAddress, "qbtc1abc")
    }

    func testHealthDecodesAndReportsHealthy() throws {
        let json = #"{"status":"healthy","setup_loaded":true}"#.data(using: .utf8)!
        let health = try JSONDecoder().decode(ProofServiceHealth.self, from: json)
        XCTAssertEqual(health.status, "healthy")
        XCTAssertTrue(health.setupLoaded)
        XCTAssertTrue(health.isHealthy)
    }

    func testHealthIsHealthyRequiresBothStatusAndSetupLoaded() throws {
        let degraded = try JSONDecoder().decode(
            ProofServiceHealth.self,
            from: #"{"status":"degraded","setup_loaded":true}"#.data(using: .utf8)!
        )
        XCTAssertFalse(degraded.isHealthy)

        let setupNotLoaded = try JSONDecoder().decode(
            ProofServiceHealth.self,
            from: #"{"status":"healthy","setup_loaded":false}"#.data(using: .utf8)!
        )
        XCTAssertFalse(setupNotLoaded.isHealthy)
    }

    // MARK: - TargetType wiring

    func testTargetTypeHealthIsGet() {
        let target: TargetType = QBTCProofServiceAPI.health
        XCTAssertEqual(target.method, .get)
        XCTAssertEqual(target.path, "/health")
        XCTAssertEqual(target.baseURL.absoluteString, Endpoint.qbtcProofServiceBaseURL)
    }

    func testTargetTypeProveIsPostWithLongTimeout() {
        let request = ClaimProofRequest(
            rHex: "01", sHex: "02", compressedPubkeyHex: "03",
            utxos: [ClaimableUtxo(txid: String(repeating: "aa", count: 32), vout: 0, amount: 1)],
            claimerAddress: "qbtc1abc",
            chainId: QBTCClaimConfig.chainId
        )
        let target: TargetType = QBTCProofServiceAPI.prove(request)
        XCTAssertEqual(target.method, .post)
        XCTAssertEqual(target.path, "/prove")
        // The proof step can take up to 5 minutes — easy to forget to bump the timeout.
        XCTAssertEqual(target.timeoutInterval, 300)
    }
}
