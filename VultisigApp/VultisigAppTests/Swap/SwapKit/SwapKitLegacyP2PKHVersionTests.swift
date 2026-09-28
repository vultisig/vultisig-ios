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
//     byte-identical to WalletCore's OWN legacy Bitcoin signer for a v1
//     PSBT. This is a genuine differential test, not the new code compared
//     to itself: `WalletCoreOracle` below reconstructs the exact pre-#5483
//     algorithm — `buildSigningInput` (verified unchanged since f18ce993d
//     via `git diff`, see the wiki plan) feeding WalletCore's own
//     `TransactionCompiler.preImageHashes` / `.compileWithSignatures`
//     directly — and the tests assert the new direct-sighash path matches
//     that independent oracle exactly, for every v1 fixture. A hard-coded
//     golden would go stale the moment the fixture (or the test key) needed
//     to change, as happened twice already in this file's history; the live
//     oracle can't go stale, because it's computed from the same WalletCore
//     binary CI links against.
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

    // MARK: - v1 regression (differential against WalletCore's own legacy signer)

    func testDogeV1SigningMatchesWalletCoreOracle() throws {
        let payload = try makeDogePayload(base64: loadBase64(fixture: "v3-real-doge-swap"))
        try assertV1MatchesWalletCoreOracle(
            payload: payload,
            coin: .dogecoin,
            buildSigningInput: SwapKitDogeSigner.buildSigningInput,
            preSigningHashes: { try SwapKitDogeSigner.preSigningHashes(payload: $0, pubKeyHex: SigningGoldenSigner.publicKeyHex(for: .secp256k1)) },
            compileSignedTransaction: SwapKitDogeSigner.compileSignedTransaction
        )
    }

    func testBchV1SigningMatchesWalletCoreOracle() throws {
        let payload = try makeBchPayload(base64: loadBase64(fixture: "v3-real-bch-swap"))
        try assertV1MatchesWalletCoreOracle(
            payload: payload,
            coin: .bitcoinCash,
            buildSigningInput: SwapKitBCHSigner.buildSigningInput,
            preSigningHashes: { try SwapKitBCHSigner.preSigningHashes(payload: $0, pubKeyHex: SigningGoldenSigner.publicKeyHex(for: .secp256k1)) },
            compileSignedTransaction: SwapKitBCHSigner.compileSignedTransaction
        )
    }

    func testDashV1SigningMatchesWalletCoreOracle() throws {
        let payload = try makeDashPayload(base64: loadBase64(fixture: "v3-real-dash-swap"))
        try assertV1MatchesWalletCoreOracle(
            payload: payload,
            coin: .dash,
            buildSigningInput: SwapKitDashSigner.buildSigningInput,
            preSigningHashes: { try SwapKitDashSigner.preSigningHashes(payload: $0, pubKeyHex: SigningGoldenSigner.publicKeyHex(for: .secp256k1)) },
            compileSignedTransaction: SwapKitDashSigner.compileSignedTransaction
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
            preSigningHashes: { try SwapKitDogeSigner.preSigningHashes(payload: $0, pubKeyHex: SigningGoldenSigner.publicKeyHex(for: .secp256k1)) },
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
            preSigningHashes: { try SwapKitBCHSigner.preSigningHashes(payload: $0, pubKeyHex: SigningGoldenSigner.publicKeyHex(for: .secp256k1)) },
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
            preSigningHashes: { try SwapKitDashSigner.preSigningHashes(payload: $0, pubKeyHex: SigningGoldenSigner.publicKeyHex(for: .secp256k1)) },
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
            preSigningHashes: { try SwapKitDogeSigner.preSigningHashes(payload: $0, pubKeyHex: SigningGoldenSigner.publicKeyHex(for: .secp256k1)) },
            compileSignedTransaction: SwapKitDogeSigner.compileSignedTransaction
        )
    }

    // MARK: - Version 3 is rejected (issue #5483)

    func testDogeV3IsRejectedWithTypedError() throws {
        let v1Base64 = try loadBase64(fixture: "v3-real-doge-swap")
        let v3Base64 = try PSBTVersionPatcher.patch(base64: v1Base64, version: 3)
        let payload = try makeDogePayload(base64: v3Base64)
        XCTAssertThrowsError(try SwapKitDogeSigner.preSigningHashes(payload: payload, pubKeyHex: SigningGoldenSigner.publicKeyHex(for: .secp256k1))) { err in
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
        XCTAssertThrowsError(try SwapKitBCHSigner.preSigningHashes(payload: payload, pubKeyHex: SigningGoldenSigner.publicKeyHex(for: .secp256k1))) { err in
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
        XCTAssertThrowsError(try SwapKitDashSigner.preSigningHashes(payload: payload, pubKeyHex: SigningGoldenSigner.publicKeyHex(for: .secp256k1))) { err in
            guard case SwapKitDashSignerError.underlying(let inner) = err else {
                return XCTFail("expected wrapped SwapKitLegacyP2PKHSignerError, got \(err)")
            }
            guard case .unsupportedVersion(let version) = inner else {
                return XCTFail("expected .unsupportedVersion, got \(inner)")
            }
            XCTAssertEqual(version, 3)
        }
    }

    // MARK: - Input locked to a different key is rejected (issue #5483 review follow-up)
    //
    // Checked at `preSigningHashes` — the message handed to the MPC network
    // — not just at `compileSignedTransaction`: rejecting only post-signing
    // would be too late, since a signature over an unowned input would
    // already exist. `compileSignedTransaction` carries the identical guard
    // as defense in depth and isn't separately tested here.

    func testDogeRejectsInputLockedToADifferentKey() throws {
        let mismatched = try PSBTInputKeyPatcher.patchInputKeyHash(
            base64: loadBase64(fixture: "v3-real-doge-swap"),
            to: Data(repeating: 0x11, count: 20)
        )
        let payload = try makeDogePayload(base64: mismatched)
        XCTAssertThrowsError(try SwapKitDogeSigner.preSigningHashes(
            payload: payload,
            pubKeyHex: SigningGoldenSigner.publicKeyHex(for: .secp256k1)
        )) { err in
            guard case SwapKitDogeSignerError.underlying(let inner) = err else {
                return XCTFail("expected wrapped SwapKitLegacyP2PKHSignerError, got \(err)")
            }
            guard case .pubkeyDoesNotMatchInput(let inputIndex) = inner else {
                return XCTFail("expected .pubkeyDoesNotMatchInput, got \(inner)")
            }
            XCTAssertEqual(inputIndex, 0)
        }
    }

    func testBchRejectsInputLockedToADifferentKey() throws {
        let mismatched = try PSBTInputKeyPatcher.patchInputKeyHash(
            base64: loadBase64(fixture: "v3-real-bch-swap"),
            to: Data(repeating: 0x11, count: 20)
        )
        let payload = try makeBchPayload(base64: mismatched)
        XCTAssertThrowsError(try SwapKitBCHSigner.preSigningHashes(
            payload: payload,
            pubKeyHex: SigningGoldenSigner.publicKeyHex(for: .secp256k1)
        )) { err in
            guard case SwapKitBCHSignerError.underlying(let inner) = err else {
                return XCTFail("expected wrapped SwapKitLegacyP2PKHSignerError, got \(err)")
            }
            guard case .pubkeyDoesNotMatchInput(let inputIndex) = inner else {
                return XCTFail("expected .pubkeyDoesNotMatchInput, got \(inner)")
            }
            XCTAssertEqual(inputIndex, 0)
        }
    }

    func testDashRejectsInputLockedToADifferentKey() throws {
        let mismatched = try PSBTInputKeyPatcher.patchInputKeyHash(
            base64: loadBase64(fixture: "v3-real-dash-swap"),
            to: Data(repeating: 0x11, count: 20)
        )
        let payload = try makeDashPayload(base64: mismatched)
        XCTAssertThrowsError(try SwapKitDashSigner.preSigningHashes(
            payload: payload,
            pubKeyHex: SigningGoldenSigner.publicKeyHex(for: .secp256k1)
        )) { err in
            guard case SwapKitDashSignerError.underlying(let inner) = err else {
                return XCTFail("expected wrapped SwapKitLegacyP2PKHSignerError, got \(err)")
            }
            guard case .pubkeyDoesNotMatchInput(let inputIndex) = inner else {
                return XCTFail("expected .pubkeyDoesNotMatchInput, got \(inner)")
            }
            XCTAssertEqual(inputIndex, 0)
        }
    }

    // MARK: - Shared assertions

    /// Differential proof for a v1 PSBT: computes the pre-image hashes and
    /// the fully assembled/signed transaction TWICE — once through the new
    /// direct-sighash path, once through `WalletCoreOracle` (the exact
    /// pre-#5483 algorithm, driving WalletCore's own `TransactionCompiler`
    /// directly) — and asserts they match exactly. `SigningGoldenSigner`'s
    /// fixed test key makes ECDSA signing deterministic (RFC6979), so both
    /// paths sign with the identical key and the same signature.
    private func assertV1MatchesWalletCoreOracle(
        payload: SwapKitSwapPayload,
        coin: CoinType,
        buildSigningInput: (SwapKitSwapPayload) throws -> BitcoinSigningInput,
        preSigningHashes: (SwapKitSwapPayload) throws -> [String],
        compileSignedTransaction: (SwapKitSwapPayload, [String: TssKeysignResponse], String) throws -> SignedTransactionResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let signingInput = try buildSigningInput(payload)
        let oracleHashes = try WalletCoreOracle.preSigningHashes(input: signingInput, coin: coin)

        let newHashes = try preSigningHashes(payload)
        XCTAssertEqual(newHashes, oracleHashes, "pre-image hashes must match WalletCore's own legacy signer for a v1 PSBT", file: file, line: line)

        let pubKeyHex = SigningGoldenSigner.publicKeyHex(for: .secp256k1)
        let signatures = try SigningGoldenSigner.signatures(forImageHashes: oracleHashes, curve: .secp256k1)
        let oracleSigned = try WalletCoreOracle.compileSignedTransaction(
            input: signingInput, coin: coin, signatures: signatures, pubKeyHex: pubKeyHex
        )
        let newSigned = try compileSignedTransaction(payload, signatures, pubKeyHex)

        XCTAssertEqual(newSigned.rawTransaction, oracleSigned.rawTransaction, "raw tx must match WalletCore's own legacy signer for a v1 PSBT", file: file, line: line)
        XCTAssertEqual(newSigned.transactionHash, oracleSigned.transactionHash, "txid must match WalletCore's own legacy signer for a v1 PSBT", file: file, line: line)
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

    /// Every test in this file signs with `SigningGoldenSigner`'s fixed key,
    /// but the committed fixtures were captured from real third-party swaps
    /// (their input is locked to some other, unknown key). Re-point the
    /// input's P2PKH key hash at our own signing key so signing actually
    /// succeeds the ownership check added for the mismatched-key regression
    /// below — the fixture's own recipient/change outputs are untouched.
    private func loadBase64(fixture: String) throws -> String {
        let response = try SwapKitFixtureLoader.decode(SwapKitSwapResponse.self, from: fixture)
        let base64: String
        switch response.tx {
        case .dogecoinPsbt(let value), .bitcoinCashPsbt(let value), .dashPsbt(let value):
            base64 = value
        default:
            throw NSError(domain: "test", code: 0, userInfo: [NSLocalizedDescriptionKey: "unexpected tx case for \(fixture)"])
        }
        return try PSBTInputKeyPatcher.patchToTestKey(base64: base64)
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

// MARK: - WalletCore oracle (the exact pre-#5483 algorithm)

/// Reconstructs `SwapKitLegacyP2PKHSigner`'s pre-#5483 `preSigningHashes` /
/// `compileSignedTransaction` verbatim (confirmed byte-for-byte against
/// `git show f18ce993d:.../SwapKitLegacyP2PKHSigner.swift` — see the wiki
/// plan), driving WalletCore's own `TransactionCompiler` directly rather
/// than calling anything this PR touched. `buildSigningInput` (which builds
/// its `BitcoinSigningInput` input) is unchanged since f18ce993d too, save
/// for two guards that moved to a shared validator with no behavior change
/// (also diffed in the wiki plan). This makes the oracle a genuine
/// independent implementation, not the new sighash code compared to itself.
private enum WalletCoreOracle {
    enum OracleError: Error { case compilerError(String) }

    static func preSigningHashes(input: BitcoinSigningInput, coin: CoinType) throws -> [String] {
        let serialized = try input.serializedData()
        let preHashesBytes = TransactionCompiler.preImageHashes(coinType: coin, txInputData: serialized)
        let preSignOutputs = try BitcoinPreSigningOutput(serializedBytes: preHashesBytes)
        guard preSignOutputs.errorMessage.isEmpty else {
            throw OracleError.compilerError(preSignOutputs.errorMessage)
        }
        return preSignOutputs.hashPublicKeys
            .map { $0.dataHash.hexString }
            .sorted()
    }

    static func compileSignedTransaction(
        input: BitcoinSigningInput,
        coin: CoinType,
        signatures: [String: TssKeysignResponse],
        pubKeyHex: String
    ) throws -> SignedTransactionResult {
        guard let pubkeyData = Data(hexString: pubKeyHex),
              let publicKey = PublicKey(data: pubkeyData, type: .secp256k1)
        else {
            throw OracleError.compilerError("invalid public key")
        }
        let serialized = try input.serializedData()
        let preHashesBytes = TransactionCompiler.preImageHashes(coinType: coin, txInputData: serialized)
        let preSignOutputs = try BitcoinPreSigningOutput(serializedBytes: preHashesBytes)
        guard preSignOutputs.errorMessage.isEmpty else {
            throw OracleError.compilerError(preSignOutputs.errorMessage)
        }
        let allSignatures = DataVector()
        let publicKeys = DataVector()
        let signatureProvider = SignatureProvider(signatures: signatures)
        for h in preSignOutputs.hashPublicKeys {
            let preImageHash = h.dataHash
            let signature = signatureProvider.getDerSignature(preHash: preImageHash)
            guard publicKey.verifyAsDER(signature: signature, message: preImageHash) else {
                throw OracleError.compilerError("signature did not verify")
            }
            allSignatures.add(data: signature)
            publicKeys.add(data: pubkeyData)
        }
        let compileBytes = TransactionCompiler.compileWithSignatures(
            coinType: coin,
            txInputData: serialized,
            signatures: allSignatures,
            publicKeys: publicKeys
        )
        let output = try BitcoinSigningOutput(serializedBytes: compileBytes)
        guard output.errorMessage.isEmpty else {
            throw OracleError.compilerError(output.errorMessage)
        }
        return SignedTransactionResult(
            rawTransaction: output.encoded.hexString,
            transactionHash: output.transactionID
        )
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

// MARK: - Test-only PSBT input key-hash patcher

/// Test-only: patches the hash160 embedded in the single `NON_WITNESS_UTXO`
/// input record's referenced P2PKH output (the UTXO being spent), leaving
/// every other byte — including the unsigned tx's own output scripts —
/// untouched, EXCEPT the unsigned tx's own input outpoint hash, which is
/// recomputed to keep the PSBT internally consistent (the outpoint must
/// still reference the NON_WITNESS_UTXO's actual, now-patched, transaction).
/// Every fixture in every test file that uses this has exactly one input
/// and one output in its embedded prev-tx. Not `private` — reused by the
/// structural DOGE/BCH/DASH test files, which sign nothing but still need a
/// self-consistent input once `preSigningHashes` requires a matching key.
enum PSBTInputKeyPatcher {
    /// hash160 of `SigningGoldenSigner.publicKeyHex(for: .secp256k1)` — the
    /// only private key these tests actually hold, so it's the only key any
    /// test in this suite can sign a matching input with.
    static let testKeyHash: Data = {
        let pubkey = Data(hexString: SigningGoldenSigner.publicKeyHex(for: .secp256k1))!
        return Hash.ripemd(data: Hash.sha256(data: pubkey))
    }()

    /// Re-points a fixture's input at `testKeyHash` so it signs successfully
    /// once ownership is enforced. The committed fixtures were captured from
    /// real third-party swaps (their input is locked to some other, unknown
    /// key); this makes the input's key self-consistent with the only
    /// private key this test suite holds.
    static func patchToTestKey(base64: String) throws -> String {
        try patchInputKeyHash(base64: base64, to: testKeyHash)
    }

    static func patchInputKeyHash(base64: String, to newHash: Data) throws -> String {
        guard newHash.count == 20 else { throw PSBTVersionPatchError.malformed }
        guard var bytes = Data(base64Encoded: base64) else { throw PSBTVersionPatchError.malformed }

        // Locate the global unsigned-tx record; its (single) input's
        // outpoint hash needs patching once we know the NEW embedded
        // prev-tx's actual hash, below.
        var offset = bytes.startIndex + 5
        var unsignedTxValueStart = -1
        while true {
            guard offset < bytes.endIndex else { throw PSBTVersionPatchError.malformed }
            let keyLen = Int(bytes[offset])
            offset += 1
            if keyLen == 0 { break }
            let keyStart = offset
            offset += keyLen
            let valueLen = Int(bytes[offset])
            offset += 1
            let valueStart = offset
            offset += valueLen
            if keyLen == 1, bytes[keyStart] == 0x00 {
                unsignedTxValueStart = valueStart
            }
        }
        guard unsignedTxValueStart >= 0 else { throw PSBTVersionPatchError.malformed }

        // Find the input map's NON_WITNESS_UTXO record (key `0x00`).
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
            guard keyLen == 1, bytes[keyStart] == 0x00 else { continue }

            // The value is the full embedded prev-tx: version(4) + inputs +
            // outputs + locktime(4). Patch every output's P2PKH hash160
            // (`76 a9 14 <20> 88 ac`, hash at bytes 3..<23 of the script).
            var p = valueStart + 4
            let inCount = Int(bytes[p])
            p += 1
            for _ in 0..<inCount {
                p += 32 + 4
                let sigLen = Int(bytes[p])
                p += 1
                p += sigLen
                p += 4
            }
            let outCount = Int(bytes[p])
            p += 1
            for _ in 0..<outCount {
                p += 8
                let scriptLen = Int(bytes[p])
                p += 1
                let scriptStart = p
                bytes.replaceSubrange((scriptStart + 3)..<(scriptStart + 23), with: newHash)
                p += scriptLen
            }

            // The unsigned tx's input references this prev-tx by hash
            // (internal little-endian wire order, i.e. the raw hash256
            // output with no further byte reversal). Recompute it now that
            // the prev-tx's content changed, or the PSBT would reference a
            // transaction that no longer matches its own embedded UTXO.
            let patchedPrevTx = bytes.subdata(in: valueStart..<(valueStart + valueLen))
            let newPrevTxId = Hash.sha256SHA256(data: patchedPrevTx)
            let unsignedTxPrevTxIdStart = unsignedTxValueStart + 4 + 1 // version(4) + input-count(1)
            bytes.replaceSubrange(unsignedTxPrevTxIdStart..<(unsignedTxPrevTxIdStart + 32), with: newPrevTxId)

            return bytes.base64EncodedString()
        }
    }
}
