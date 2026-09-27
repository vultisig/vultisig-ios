//
//  SwapKitLegacyP2PKHVersionTests.swift
//  VultisigAppTests
//
//  Issue #5483: SwapKit now ships DOGE/BCH/DASH PSBTs whose unsigned tx can
//  be version 2; the legacy P2PKH signer parsed version/locktime but never
//  applied them, so WalletCore's legacy Bitcoin signer silently re-versioned
//  every broadcast to 1. This file pins two contracts across the direct
//  sighash+assembly rewrite:
//
//  1. v1 regression — pre-image hashes and the assembled transaction stay
//     byte-identical to the WalletCore-driven implementation that shipped
//     before this fix. Golden values below were captured by running the
//     pre-fix code against the committed v1 fixtures with a fixed
//     deterministic test key (`SigningGoldenSigner`).
//  2. v2 handling — version/locktime are preserved from the PSBT, version 3
//     is rejected with a typed error, and the signed transaction's inputs
//     and outputs (everything except scriptSig, which only exists once
//     signed) match the PSBT's unsigned tx exactly.
//
//  Note on txid: unlike the BTC/segwit PSBT path, a legacy P2PKH scriptSig
//  carries the signature and IS part of the txid preimage (Bitcoin has no
//  witness discount pre-segwit). The PSBT's "unsigned tx" always has empty
//  scriptSigs by protocol, so its hash never equals the real broadcast
//  txid — for v1 or v2. What we CAN and do pin: the signed tx's inputs and
//  outputs are byte-identical to the PSBT's (the frozen plan held), and the
//  reported `transactionHash` is exactly hash256(rawTransaction) reversed.
//

import BigInt
import Foundation
import Tss
import WalletCore
import XCTest
@testable import VultisigApp

@MainActor
final class SwapKitLegacyP2PKHVersionTests: XCTestCase {

    // MARK: - v1 regression (byte-identical to the pre-#5483-fix WalletCore path)

    func testDogeV1SigningIsByteIdenticalToPreFixGolden() throws {
        let payload = try makeDogePayload(base64: loadBase64(fixture: "v3-real-doge-swap"))
        try assertV1Golden(
            payload: payload,
            preSigningHashes: SwapKitDogeSigner.preSigningHashes,
            compileSignedTransaction: SwapKitDogeSigner.compileSignedTransaction,
            expectedHashes: ["30d6ff2d31e934a1d32c37b8ea8e55c2d312291201b7017e25d6e2b17a50906a"],
            expectedRawTransaction: "010000000150e47ac786c07578b8e92d014b46854300b2c7b7395eb72ccc0727e5443a5ab4000000006b4830450221008584ece98bb35f06d30c82e83f3142a369764caabe35f387c8ebcbadd065d68b02206f71a2429b3984ca55c2cc628873376fac975eb229022caa52b7a52cdf9dc957012103a524739c987b6e5b8cb2340ad77b63a69253d93187aa5b334cab8f8144702687ffffffff02d0b08a3c170000001976a91419fb7ab04f2de927ced3b8337ab45d5d046db6cf88ac00c2eb0b000000001976a914c4919dca916dc416c06d51cb1940a7ba268c475d88ac00000000",
            expectedTransactionHash: "b52c634511ab22d0c5fd5a72da1781f108340c5e61f14440f00751919a2f7b7f"
        )
    }

    func testBchV1SigningIsByteIdenticalToPreFixGolden() throws {
        let payload = try makeBchPayload(base64: loadBase64(fixture: "v3-real-bch-swap"))
        try assertV1Golden(
            payload: payload,
            preSigningHashes: SwapKitBCHSigner.preSigningHashes,
            compileSignedTransaction: SwapKitBCHSigner.compileSignedTransaction,
            expectedHashes: ["4d0c3edbae26aeb12f486e5a91b7a8f0700d4b77f68c98237e63fe7089d8fc99"],
            expectedRawTransaction: "010000000183bb97c24c0e9d34f160fe21ccda7832ec1e070d7968e35ffe41f5de374633a3000000006b483045022100afd17d179cf9d986645229d90130cc1d22488a6c9250d0a3607f24763346a37a022046b58f99880dc973e8103182b93aeb495d03c3daa731609a1d43865a65712e81412103a524739c987b6e5b8cb2340ad77b63a69253d93187aa5b334cab8f8144702687ffffffff02141af702000000001976a91476a04053bda0a88bda5177b86a15c3b29f55987388ac90d00300000000001976a91476a04053bda0a88bda5177b86a15c3b29f55987388ac00000000",
            expectedTransactionHash: "bdf995eb37656eb2f11cc3ba7de700b26919ec7e1bd442a371e81f4698f72668"
        )
    }

    func testDashV1SigningIsByteIdenticalToPreFixGolden() throws {
        let payload = try makeDashPayload(base64: loadBase64(fixture: "v3-real-dash-swap"))
        try assertV1Golden(
            payload: payload,
            preSigningHashes: SwapKitDashSigner.preSigningHashes,
            compileSignedTransaction: SwapKitDashSigner.compileSignedTransaction,
            expectedHashes: ["f81468f5a0d83c215d2eea28c246ee776c551dc9a72f6da7114ad7169d1c14bc"],
            expectedRawTransaction: "01000000019d7ddfe60d82f4a419e044dbfd8f2a01b87a5333e328df0b7d76cfff718cdf41000000006a47304402204eb17129bb43a3d7ff6caf20391fdf6296b58f5d7b63f9da965ec61a58a1a31b022054bd15f4665253b5d4c49068c21c34456cfa90b67344ab57dec92e79b0267d6a012103a524739c987b6e5b8cb2340ad77b63a69253d93187aa5b334cab8f8144702687ffffffff02d099373b000000001976a9141b2a522cc8d42b0be7ceb8db711416794d50c84688aca02e6300000000001976a9141b2a522cc8d42b0be7ceb8db711416794d50c84688ac00000000",
            expectedTransactionHash: "838bb5a6aac778bdb2fe5e3cfa329dd0b7331bb674ffc7d3dacfc4487811a0bf"
        )
    }

    // MARK: - v2 preserves version/locktime (new behavior, issue #5483)

    func testDogeV2PreservesVersionAndMatchesFrozenPlan() throws {
        let v1Base64 = try loadBase64(fixture: "v3-real-doge-swap")
        let v2Base64 = try PSBTVersionPatcher.patch(base64: v1Base64, version: 2)
        let payload = try makeDogePayload(base64: v2Base64)
        try assertVersionPreserved(
            payload: payload,
            psbtBase64: v2Base64,
            expectedVersion: 2,
            expectedLocktime: 0,
            preSigningHashes: SwapKitDogeSigner.preSigningHashes,
            compileSignedTransaction: SwapKitDogeSigner.compileSignedTransaction
        )
    }

    func testBchV2PreservesVersionAndMatchesFrozenPlan() throws {
        let v1Base64 = try loadBase64(fixture: "v3-real-bch-swap")
        let v2Base64 = try PSBTVersionPatcher.patch(base64: v1Base64, version: 2)
        let payload = try makeBchPayload(base64: v2Base64)
        try assertVersionPreserved(
            payload: payload,
            psbtBase64: v2Base64,
            expectedVersion: 2,
            expectedLocktime: 0,
            preSigningHashes: SwapKitBCHSigner.preSigningHashes,
            compileSignedTransaction: SwapKitBCHSigner.compileSignedTransaction
        )
    }

    func testDashV2PreservesVersionAndMatchesFrozenPlan() throws {
        let v1Base64 = try loadBase64(fixture: "v3-real-dash-swap")
        let v2Base64 = try PSBTVersionPatcher.patch(base64: v1Base64, version: 2)
        let payload = try makeDashPayload(base64: v2Base64)
        try assertVersionPreserved(
            payload: payload,
            psbtBase64: v2Base64,
            expectedVersion: 2,
            expectedLocktime: 0,
            preSigningHashes: SwapKitDashSigner.preSigningHashes,
            compileSignedTransaction: SwapKitDashSigner.compileSignedTransaction
        )
    }

    // MARK: - Non-zero locktime is preserved (issue #5483)

    func testDogeV2WithNonZeroLocktimeIsPreserved() throws {
        let v1Base64 = try loadBase64(fixture: "v3-real-doge-swap")
        let patched = try PSBTVersionPatcher.patch(base64: v1Base64, version: 2, locktime: 700_000)
        let payload = try makeDogePayload(base64: patched)
        try assertVersionPreserved(
            payload: payload,
            psbtBase64: patched,
            expectedVersion: 2,
            expectedLocktime: 700_000,
            preSigningHashes: SwapKitDogeSigner.preSigningHashes,
            compileSignedTransaction: SwapKitDogeSigner.compileSignedTransaction
        )
    }

    // MARK: - Version 3 is rejected (issue #5483)

    func testDogeV3IsRejectedWithTypedError() throws {
        let v1Base64 = try loadBase64(fixture: "v3-real-doge-swap")
        let v3Base64 = try PSBTVersionPatcher.patch(base64: v1Base64, version: 3)
        let payload = try makeDogePayload(base64: v3Base64)
        XCTAssertThrowsError(try SwapKitDogeSigner.preSigningHashes(payload: payload)) { err in
            guard case SwapKitDogeSignerError.underlying(let inner) = err else {
                return XCTFail("expected wrapped SwapKitLegacyP2PKHSignerError, got \(err)")
            }
            guard case .unsupportedVersion(let version) = inner else {
                return XCTFail("expected .unsupportedVersion, got \(inner)")
            }
            XCTAssertEqual(version, 3)
        }
    }

    func testBchV3IsRejectedWithTypedError() throws {
        let v1Base64 = try loadBase64(fixture: "v3-real-bch-swap")
        let v3Base64 = try PSBTVersionPatcher.patch(base64: v1Base64, version: 3)
        let payload = try makeBchPayload(base64: v3Base64)
        XCTAssertThrowsError(try SwapKitBCHSigner.preSigningHashes(payload: payload)) { err in
            guard case SwapKitBCHSignerError.underlying(let inner) = err else {
                return XCTFail("expected wrapped SwapKitLegacyP2PKHSignerError, got \(err)")
            }
            guard case .unsupportedVersion(let version) = inner else {
                return XCTFail("expected .unsupportedVersion, got \(inner)")
            }
            XCTAssertEqual(version, 3)
        }
    }

    func testDashV3IsRejectedWithTypedError() throws {
        let v1Base64 = try loadBase64(fixture: "v3-real-dash-swap")
        let v3Base64 = try PSBTVersionPatcher.patch(base64: v1Base64, version: 3)
        let payload = try makeDashPayload(base64: v3Base64)
        XCTAssertThrowsError(try SwapKitDashSigner.preSigningHashes(payload: payload)) { err in
            guard case SwapKitDashSignerError.underlying(let inner) = err else {
                return XCTFail("expected wrapped SwapKitLegacyP2PKHSignerError, got \(err)")
            }
            guard case .unsupportedVersion(let version) = inner else {
                return XCTFail("expected .unsupportedVersion, got \(inner)")
            }
            XCTAssertEqual(version, 3)
        }
    }

    // MARK: - Shared assertions

    /// Pins pre-image hashes + assembled signed transaction against a
    /// captured pre-fix golden. `SigningGoldenSigner`'s fixed test key makes
    /// ECDSA signing deterministic (RFC6979), so the same PSBT + key always
    /// produces the same signature and therefore the same raw tx bytes.
    private func assertV1Golden(
        payload: SwapKitSwapPayload,
        preSigningHashes: (SwapKitSwapPayload) throws -> [String],
        compileSignedTransaction: (SwapKitSwapPayload, [String: TssKeysignResponse], String) throws -> SignedTransactionResult,
        expectedHashes: [String],
        expectedRawTransaction: String,
        expectedTransactionHash: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let hashes = try preSigningHashes(payload)
        XCTAssertEqual(hashes, expectedHashes, "pre-image hashes drifted from the pre-fix golden", file: file, line: line)
        let signatures = try SigningGoldenSigner.signatures(forImageHashes: hashes, curve: .secp256k1)
        let signed = try compileSignedTransaction(payload, signatures, SigningGoldenSigner.publicKeyHex(for: .secp256k1))
        XCTAssertEqual(signed.rawTransaction, expectedRawTransaction, "raw tx drifted from the pre-fix golden", file: file, line: line)
        XCTAssertEqual(signed.transactionHash, expectedTransactionHash, "txid drifted from the pre-fix golden", file: file, line: line)
    }

    /// Signs `payload` end-to-end and checks: the raw tx's version/locktime
    /// match what was requested, the reported txid is exactly
    /// hash256(rawTransaction) reversed, and every input/output the signed
    /// tx carries (outpoints, sequences, amounts, scriptPubKeys) matches the
    /// PSBT's unsigned tx exactly — the frozen plan held, only scriptSig
    /// differs (it doesn't exist before signing).
    private func assertVersionPreserved(
        payload: SwapKitSwapPayload,
        psbtBase64: String,
        expectedVersion: UInt32,
        expectedLocktime: UInt32,
        preSigningHashes: (SwapKitSwapPayload) throws -> [String],
        compileSignedTransaction: (SwapKitSwapPayload, [String: TssKeysignResponse], String) throws -> SignedTransactionResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let hashes = try preSigningHashes(payload)
        let signatures = try SigningGoldenSigner.signatures(forImageHashes: hashes, curve: .secp256k1)
        let signed = try compileSignedTransaction(payload, signatures, SigningGoldenSigner.publicKeyHex(for: .secp256k1))
        let rawBytes = try XCTUnwrap(Data(hexString: signed.rawTransaction), file: file, line: line)

        XCTAssertEqual(rawBytes.prefix(4), leUInt32(expectedVersion), "signed tx version must match the PSBT's", file: file, line: line)
        XCTAssertEqual(rawBytes.suffix(4), leUInt32(expectedLocktime), "signed tx locktime must match the PSBT's", file: file, line: line)

        let expectedHash = Data(Hash.sha256SHA256(data: rawBytes).reversed()).hexString
        XCTAssertEqual(signed.transactionHash, expectedHash, "reported txid must be hash256(rawTransaction) reversed", file: file, line: line)

        let unsignedTx = try parseUnsignedTx(base64: psbtBase64)
        let signedIO = try parseInputsAndOutputsIgnoringScriptSig(rawBytes)
        XCTAssertEqual(signedIO.inputs, unsignedTx.inputs, "signed tx inputs (outpoint+sequence) must match the PSBT's frozen plan", file: file, line: line)
        XCTAssertEqual(signedIO.outputs, unsignedTx.outputs, "signed tx outputs must match the PSBT's frozen plan", file: file, line: line)
    }

    // MARK: - Payload builders

    private func loadBase64(fixture: String) throws -> String {
        let response = try SwapKitFixtureLoader.decode(SwapKitSwapResponse.self, from: fixture)
        switch response.tx {
        case .dogecoinPsbt(let base64), .bitcoinCashPsbt(let base64), .dashPsbt(let base64):
            return base64
        default:
            throw NSError(domain: "test", code: 0, userInfo: [NSLocalizedDescriptionKey: "unexpected tx case for \(fixture)"])
        }
    }

    private func makeDogePayload(base64: String) throws -> SwapKitSwapPayload {
        let bytes = try XCTUnwrap(Data(base64Encoded: base64))
        return SwapKitSwapPayload(
            fromCoin: makeCoin(chain: .dogecoin, ticker: "DOGE", address: "DH5yaieqoZN36fDVciNyRueRGvGLR3mr7L"),
            toCoin: makeUsdcCoin(),
            fromAmount: BigInt(100_000_000_000),
            toAmountDecimal: 0,
            txType: "PSBT_DOGE",
            txPayload: bytes,
            targetAddress: "D9DTLZMyferY6TVquM7GryViP7GtBntqWj",
            inboundAddress: nil,
            memo: nil,
            subProvider: "NEAR",
            swapID: "test"
        )
    }

    private func makeBchPayload(base64: String) throws -> SwapKitSwapPayload {
        let bytes = try XCTUnwrap(Data(base64Encoded: base64))
        return SwapKitSwapPayload(
            fromCoin: makeCoin(chain: .bitcoinCash, ticker: "BCH", address: "qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx08"),
            toCoin: makeUsdcCoin(),
            fromAmount: BigInt(50_000_000),
            toAmountDecimal: 0,
            txType: "PSBT_BCH",
            txPayload: bytes,
            targetAddress: "",
            inboundAddress: nil,
            memo: nil,
            subProvider: "NEAR",
            swapID: "test"
        )
    }

    private func makeDashPayload(base64: String) throws -> SwapKitSwapPayload {
        let bytes = try XCTUnwrap(Data(base64Encoded: base64))
        return SwapKitSwapPayload(
            fromCoin: makeCoin(chain: .dash, ticker: "DASH", address: "XdAUmwtig27HBG6WfYyHAzP8n6XC9jESEw"),
            toCoin: makeUsdcCoin(),
            fromAmount: BigInt(1_000_000_000),
            toAmountDecimal: 0,
            txType: "PSBT_DASH",
            txPayload: bytes,
            targetAddress: "",
            inboundAddress: nil,
            memo: nil,
            subProvider: "NEAR",
            swapID: "test"
        )
    }

    private func makeCoin(chain: Chain, ticker: String, address: String) -> Coin {
        let meta = CoinMeta.make(chain: chain, ticker: ticker, decimals: 8, isNativeToken: true)
        return Coin(asset: meta, address: address, hexPublicKey: "")
    }

    private func makeUsdcCoin() -> Coin {
        let meta = CoinMeta.make(chain: .ethereum, ticker: "USDC", decimals: 6, isNativeToken: false)
        return Coin(asset: meta, address: "0xtest", hexPublicKey: "")
    }

    // MARK: - Raw-byte helpers

    private func leUInt32(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    private struct RawIO: Equatable {
        struct Input: Equatable { let prevTxIdLE: Data; let prevIndex: UInt32; let sequence: UInt32 }
        struct Output: Equatable { let amount: Int64; let scriptPubKey: Data }
        let inputs: [Input]
        let outputs: [Output]
    }

    /// Parses a PSBT's unsigned-tx global record (BIP-174 key `0x00`) into
    /// its inputs (scriptSig is always empty there by protocol) and outputs.
    private func parseUnsignedTx(base64: String) throws -> RawIO {
        guard let bytes = Data(base64Encoded: base64) else { throw PSBTVersionPatchError.malformed }
        var cursor = 5 // magic `psbt\xff`
        while true {
            guard cursor < bytes.count else { throw PSBTVersionPatchError.malformed }
            let keyLen = Int(bytes[bytes.startIndex + cursor])
            cursor += 1
            if keyLen == 0 { throw PSBTVersionPatchError.malformed }
            let keyStart = cursor
            cursor += keyLen
            let valueLen = Int(bytes[bytes.startIndex + cursor])
            cursor += 1
            let valueStart = cursor
            cursor += valueLen
            if keyLen == 1, bytes[bytes.startIndex + keyStart] == 0x00 {
                let value = bytes.subdata(in: (bytes.startIndex + valueStart)..<(bytes.startIndex + valueStart + valueLen))
                return try parseInputsAndOutputsIgnoringScriptSig(value)
            }
        }
    }

    /// Parses `version || inputs || outputs || locktime` — a full legacy tx
    /// and the PSBT's unsigned-tx body share this exact shape — into
    /// inputs/outputs, ignoring each input's scriptSig (present for a signed
    /// tx, always empty for the PSBT's unsigned tx).
    private func parseInputsAndOutputsIgnoringScriptSig(_ data: Data) throws -> RawIO {
        var offset = data.startIndex + 4 // skip version
        func readVarInt() throws -> UInt64 {
            let first = data[offset]
            offset += 1
            switch first {
            case 0..<0xfd:
                return UInt64(first)
            case 0xfd:
                let v = data.subdata(in: offset..<offset + 2).withUnsafeBytes { $0.load(as: UInt16.self) }
                offset += 2
                return UInt64(UInt16(littleEndian: v))
            default:
                throw PSBTVersionPatchError.malformed
            }
        }
        let inCount = try readVarInt()
        var inputs: [RawIO.Input] = []
        for _ in 0..<inCount {
            let prevTxIdLE = data.subdata(in: offset..<offset + 32)
            offset += 32
            let prevIndex = data.subdata(in: offset..<offset + 4).withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
            offset += 4
            let scriptLen = try readVarInt()
            offset += Int(scriptLen)
            let sequence = data.subdata(in: offset..<offset + 4).withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
            offset += 4
            inputs.append(RawIO.Input(prevTxIdLE: prevTxIdLE, prevIndex: prevIndex, sequence: sequence))
        }
        let outCount = try readVarInt()
        var outputs: [RawIO.Output] = []
        for _ in 0..<outCount {
            let amount = data.subdata(in: offset..<offset + 8).withUnsafeBytes { $0.load(as: Int64.self) }.littleEndian
            offset += 8
            let scriptLen = try readVarInt()
            offset += Int(scriptLen)
            let scriptStart = offset - Int(scriptLen)
            outputs.append(RawIO.Output(amount: amount, scriptPubKey: data.subdata(in: scriptStart..<offset)))
        }
        return RawIO(inputs: inputs, outputs: outputs)
    }
}

// MARK: - Test-only PSBT version/locktime patcher

private enum PSBTVersionPatchError: Error { case malformed }

/// Test-only: patches the 4-byte version and/or locktime fields inside a
/// PSBT's global unsigned-tx record (BIP-174 key `0x00`), leaving every
/// other byte untouched — synthesizes version-2 / version-3 /
/// non-zero-locktime variants of a real captured v1 fixture without
/// hand-maintaining separate PSBT blobs. Assumes single-byte CompactSize
/// key/value length prefixes, true for every fixture in this suite.
private enum PSBTVersionPatcher {
    static func patch(base64: String, version: UInt32? = nil, locktime: UInt32? = nil) throws -> String {
        guard var bytes = Data(base64Encoded: base64) else { throw PSBTVersionPatchError.malformed }
        var offset = bytes.startIndex + 5 // magic `psbt\xff`
        while true {
            guard offset < bytes.endIndex else { throw PSBTVersionPatchError.malformed }
            let keyLen = Int(bytes[offset])
            offset += 1
            if keyLen == 0 { throw PSBTVersionPatchError.malformed }
            let keyStart = offset
            offset += keyLen
            let valueLen = Int(bytes[offset])
            offset += 1
            let valueStart = offset
            offset += valueLen
            if keyLen == 1, bytes[keyStart] == 0x00 {
                if let version {
                    bytes.replaceSubrange(valueStart..<(valueStart + 4), with: withUnsafeBytes(of: version.littleEndian) { Data($0) })
                }
                if let locktime {
                    let lockStart = valueStart + valueLen - 4
                    bytes.replaceSubrange(lockStart..<(lockStart + 4), with: withUnsafeBytes(of: locktime.littleEndian) { Data($0) })
                }
                return bytes.base64EncodedString()
            }
        }
    }
}
