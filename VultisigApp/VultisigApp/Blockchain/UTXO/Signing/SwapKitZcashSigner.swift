//
//  SwapKitZcashSigner.swift
//  VultisigApp
//
//  Signs SwapKit's pre-built ZEC PSBT. The transparent ZEC tx is wrapped in
//  a BIP-174 envelope; the inner unsigned-tx body is **NU5 v5 (ZIP-225)**:
//  header `0x80000005`, version group `0x26A7270A`, consensus branch id,
//  lock time, expiry height, the transparent bundle, then three zero counts
//  for the Sapling spends/outputs and Orchard actions. Sapling v4 is refused
//  (invalid on mainnet since NU7), as are non-zero shielded bundles and
//  non-P2PKH inputs.
//
//  Sighash: ZIP-244 through `ZcashSigner` (WalletCore signing V2). SwapKit's
//  inputs, outputs (scripts verbatim) and their order are kept untouched, so
//  the signed txid is the one SwapKit/NEAR Intents tracks. The branch id comes
//  from the PSBT and must equal the live one resolved at send time.
//
//  Real fixture: `__fixtures__/v3-real-zec-v5-swap.json` (ZEC.ZEC → ETH.ETH).
//

import Foundation
import Tss
import WalletCore

enum SwapKitZcashSignerError: Error, LocalizedError {
    case unsupportedZcashVersion(version: UInt32, group: UInt32)
    case unsupportedShieldedTransaction
    case underlying(SwapKitLegacyP2PKHSignerError)

    var errorDescription: String? {
        switch self {
        case .unsupportedZcashVersion(let version, let group):
            return String(format: "swapKitErrorUnsupportedZcashVersion".localized, "0x\(String(version, radix: 16))", "0x\(String(group, radix: 16))")
        case .unsupportedShieldedTransaction:
            return "swapKitErrorUnsupportedShieldedTransaction".localized
        case .underlying(let err):
            return err.errorDescription
        }
    }
}

/// Overwinter flag (high bit) + version 5. Matches `0x05 0x00 0x00 0x80` LE.
private let nu5TxVersion: UInt32 = 0x80000005
/// NU5 consensus group ID.
private let nu5VersionGroupID: UInt32 = 0x26A7270A

enum SwapKitZcashSigner {

    /// ZIP-244 sighashes for every input, via `ZcashSigner`. `zcashBranchId` is the live branch
    /// id resolved at send time; refuses when absent or different from the PSBT's
    /// (no compiled-in fallback).
    static func preSigningHashes(payload: SwapKitSwapPayload, zcashBranchId: String?, pubKeyHex: String) throws -> [String] {
        let pubkeyData = try Self.pubkeyData(pubKeyHex)
        let v2 = try Self.ownedSigningInputV2(payload: payload, zcashBranchId: zcashBranchId, pubkeyData: pubkeyData)
        return try Self.wrap { try ZcashSigner.preImageHashes(v2Input: v2) }
            .map(\.hexString)
            .sorted()
    }

    /// Assembles the signed v5 broadcast tx; every signature is verified against its sighash.
    static func compileSignedTransaction(
        payload: SwapKitSwapPayload,
        signatures: [String: TssKeysignResponse],
        pubKeyHex: String,
        zcashBranchId: String?
    ) throws -> SignedTransactionResult {
        let pubkeyData = try Self.pubkeyData(pubKeyHex)
        guard let publicKey = PublicKey(data: pubkeyData, type: .secp256k1) else {
            throw SwapKitZcashSignerError.underlying(.invalidPublicKey(pubKeyHex))
        }
        let v2 = try Self.ownedSigningInputV2(payload: payload, zcashBranchId: zcashBranchId, pubkeyData: pubkeyData)
        return try Self.wrap { try ZcashSigner.compile(v2Input: v2, signatures: signatures, publicKey: publicKey) }
    }

    private static func pubkeyData(_ hex: String) throws -> Data {
        guard let data = Data(hexString: hex) else {
            throw SwapKitZcashSignerError.underlying(.invalidPublicKey(hex))
        }
        return data
    }

    private static func wrap<T>(_ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch let err as ZcashSignerError {
            throw SwapKitZcashSignerError.underlying(.planError(err.errorDescription ?? "\(err)"))
        }
    }

    /// Builds the signing input only after every PSBT input is confirmed to be
    /// locked to `pubkeyData`; the MPC network must never be asked to sign an
    /// input this vault does not own.
    private static func ownedSigningInputV2(
        payload: SwapKitSwapPayload,
        zcashBranchId: String?,
        pubkeyData: Data
    ) throws -> Data {
        let parsed = try parsePSBT(payload.txPayload, zcashBranchId: zcashBranchId)
        do {
            try SwapKitLegacyP2PKHSigner.verifyOwnership(inputs: parsed.inputs, pubkeyData: pubkeyData)
        } catch let err as SwapKitLegacyP2PKHSignerError {
            throw SwapKitZcashSignerError.underlying(err)
        }
        return try Self.wrap {
            try ZcashSigner.signingInputV2(
                utxos: parsed.utxos,
                outputs: parsed.outputs,
                lockTime: parsed.lockTime,
                expiryHeight: parsed.expiryHeight,
                branchID: parsed.branchID,
                publicKey: pubkeyData
            )
        }
    }

    /// Exposed for unit tests so callers can pin the v5 body parser in isolation.
    static func parseUnsignedTx(_ data: Data) throws -> ParsedZcashV5Tx {
        var cursor = PSBTCursor(data: data)
        do {
            let version = try cursor.readUInt32LE()
            let versionGroupID = try cursor.readUInt32LE()
            // Sapling v4 is invalid since NU7; anything else is an epoch we don't sign.
            guard version == nu5TxVersion, versionGroupID == nu5VersionGroupID else {
                throw SwapKitZcashSignerError.unsupportedZcashVersion(version: version, group: versionGroupID)
            }
            let branchID = try cursor.readBytes(4)
            let lockTime = try cursor.readUInt32LE()
            let expiryHeight = try cursor.readUInt32LE()
            let inputCount = try cursor.readCompactSize()
            var inputs: [(prevTxIdLE: Data, prevIndex: UInt32, sequence: UInt32)] = []
            for _ in 0..<inputCount {
                let prevBytes = try cursor.readBytes(32)
                let prevIndex = try cursor.readUInt32LE()
                let sigLen = try cursor.readCompactSize()
                _ = try cursor.readBytes(Int(sigLen))
                let sequence = try cursor.readUInt32LE()
                inputs.append((prevTxIdLE: prevBytes, prevIndex: prevIndex, sequence: sequence))
            }
            let outputCount = try cursor.readCompactSize()
            var outputs: [LegacyP2PKHOutput] = []
            for _ in 0..<outputCount {
                let amount = try cursor.readInt64LE()
                let scriptLen = try cursor.readCompactSize()
                let script = try cursor.readBytes(Int(scriptLen))
                outputs.append(LegacyP2PKHOutput(amount: amount, scriptPubKey: script))
            }
            // Transparent-only: Sapling spends, Sapling outputs and Orchard actions
            // must all be zero and nothing may follow. We can't sign shielded bundles with MPC.
            let nSaplingSpend = try cursor.readCompactSize()
            let nSaplingOutput = try cursor.readCompactSize()
            let nOrchardAction = try cursor.readCompactSize()
            guard nSaplingSpend == 0, nSaplingOutput == 0, nOrchardAction == 0, cursor.isAtEnd else {
                throw SwapKitZcashSignerError.unsupportedShieldedTransaction
            }
            return ParsedZcashV5Tx(
                version: version,
                versionGroupID: versionGroupID,
                branchID: branchID,
                lockTime: lockTime,
                expiryHeight: expiryHeight,
                inputs: inputs,
                outputs: outputs
            )
        } catch let err as SwapKitPSBTParserError {
            throw SwapKitZcashSignerError.underlying(mapParserError(err))
        }
    }

    // MARK: - Private — full PSBT walker (framing + v5 body + per-input maps)

    struct ParsedZcashPSBT {
        let inputs: [LegacyP2PKHInput]
        let utxos: [BitcoinUnspentTransaction]
        let outputs: [BitcoinV2Output]
        let branchID: Data
        let lockTime: UInt32
        let expiryHeight: UInt32
    }

    /// Exposed for unit tests: the validated inputs/outputs the signer will replay.
    static func parsePSBT(_ psbtBytes: Data, zcashBranchId: String?) throws -> ParsedZcashPSBT {
        // 1. Parse BIP-174 framing.
        let framingPrefix: (cursor: PSBTCursor, globals: [Data: Data], unsignedTxBytes: Data)
        do {
            framingPrefix = try SwapKitPSBTParser.parseFraming(psbtBytes: psbtBytes)
        } catch let err as SwapKitPSBTParserError {
            throw SwapKitZcashSignerError.underlying(mapParserError(err))
        }

        // 2. Parse the v5 body and pin its branch id to the live one.
        let parsedTx = try parseUnsignedTx(framingPrefix.unsignedTxBytes)
        try requireLiveBranchID(zcashBranchId, matches: parsedTx.branchID)

        // 3. Drain per-input + per-output maps.
        var cursor = framingPrefix.cursor
        var inputMaps: [[Data: Data]] = []
        do {
            for _ in 0..<parsedTx.inputs.count {
                inputMaps.append(try cursor.readMap())
            }
            for _ in 0..<parsedTx.outputs.count {
                _ = try cursor.readMap()
            }
        } catch let err as SwapKitPSBTParserError {
            throw SwapKitZcashSignerError.underlying(mapParserError(err))
        }

        // 4. Resolve per-input UTXO (ZEC ships WITNESS_UTXO) and require P2PKH.
        var legacyInputs: [LegacyP2PKHInput] = []
        for (index, parsedInput) in parsedTx.inputs.enumerated() {
            let (amount, scriptPubKey) = try resolvePrevUtxo(inputMap: inputMaps[index], inputIndex: index)
            let keyHash = try assertP2PKHAndExtractKeyHash(scriptPubKey: scriptPubKey, label: "input #\(index)")
            legacyInputs.append(LegacyP2PKHInput(
                prevTxIdLE: parsedInput.prevTxIdLE,
                prevIndex: parsedInput.prevIndex,
                sequence: parsedInput.sequence,
                amount: amount,
                scriptPubKey: scriptPubKey,
                keyHash: keyHash
            ))
        }

        // 5. Outputs stay verbatim and in order: P2PKH (deposit/change) or one OP_RETURN memo.
        guard !legacyInputs.isEmpty, !parsedTx.outputs.isEmpty else {
            throw SwapKitZcashSignerError.underlying(.planError("empty inputs or outputs"))
        }
        var opReturnCount = 0
        for (index, output) in parsedTx.outputs.enumerated() {
            if output.scriptPubKey.first == 0x6a, output.amount == 0 {
                opReturnCount += 1
            } else {
                _ = try assertP2PKHAndExtractKeyHash(scriptPubKey: output.scriptPubKey, label: "output #\(index)")
            }
        }
        guard opReturnCount <= 1 else {
            throw SwapKitZcashSignerError.underlying(.unsupportedScript("PSBT has \(opReturnCount) OP_RETURN outputs; expected at most 1"))
        }
        let totalIn = legacyInputs.reduce(Int64(0)) { $0 + $1.amount }
        let totalOut = parsedTx.outputs.reduce(Int64(0)) { $0 + $1.amount }
        guard totalIn >= totalOut else {
            throw SwapKitZcashSignerError.underlying(.planError("negative fee: inputs=\(totalIn) outputs=\(totalOut)"))
        }

        return ParsedZcashPSBT(
            inputs: legacyInputs,
            utxos: legacyInputs.map { input in
                BitcoinUnspentTransaction.with {
                    $0.outPoint = BitcoinOutPoint.with {
                        $0.hash = input.prevTxIdLE
                        $0.index = input.prevIndex
                        $0.sequence = input.sequence
                    }
                    $0.amount = input.amount
                    $0.script = input.scriptPubKey
                }
            },
            outputs: parsedTx.outputs.map { output in
                BitcoinV2Output.with {
                    $0.value = output.amount
                    $0.customScriptPubkey = output.scriptPubKey
                }
            },
            branchID: parsedTx.branchID,
            lockTime: parsedTx.lockTime,
            expiryHeight: parsedTx.expiryHeight
        )
    }

    /// Signing with a branch id other than the live one yields a tx the network
    /// rejects, so refuse up front when it is unresolved or different.
    private static func requireLiveBranchID(_ zcashBranchId: String?, matches psbtBranchID: Data) throws {
        guard let zcashBranchId, !zcashBranchId.isEmpty, let live = Data(hexString: zcashBranchId) else {
            throw SwapKitZcashSignerError.underlying(.planError(
                "Zcash consensus branch id is unavailable; cannot sign the SwapKit ZEC transaction without the live branch id"
            ))
        }
        guard live == psbtBranchID else {
            throw SwapKitZcashSignerError.underlying(.planError(
                "SwapKit ZEC PSBT branch id \(psbtBranchID.hexString) differs from the live branch id \(zcashBranchId)"
            ))
        }
    }

    private static func resolvePrevUtxo(
        inputMap: [Data: Data],
        inputIndex: Int
    ) throws -> (amount: Int64, scriptPubKey: Data) {
        // ZEC ships WITNESS_UTXO (key 0x01).
        if let witness = inputMap[Data([0x01])] {
            var c = PSBTCursor(data: witness)
            do {
                let amount = try c.readInt64LE()
                let scriptLen = try c.readCompactSize()
                let script = try c.readBytes(Int(scriptLen))
                return (amount, script)
            } catch let err as SwapKitPSBTParserError {
                throw SwapKitZcashSignerError.underlying(mapParserError(err))
            }
        }
        throw SwapKitZcashSignerError.underlying(.missingPrevUtxo(inputIndex: inputIndex))
    }

    private static func assertP2PKHAndExtractKeyHash(scriptPubKey: Data, label: String) throws -> Data {
        guard scriptPubKey.count == 25,
              scriptPubKey[scriptPubKey.startIndex] == 0x76,
              scriptPubKey[scriptPubKey.startIndex + 1] == 0xa9,
              scriptPubKey[scriptPubKey.startIndex + 2] == 0x14,
              scriptPubKey[scriptPubKey.startIndex + 23] == 0x88,
              scriptPubKey[scriptPubKey.startIndex + 24] == 0xac
        else {
            throw SwapKitZcashSignerError.underlying(.unsupportedScript(
                "\(label) scriptPubKey is not P2PKH: \(scriptPubKey.hexString)"
            ))
        }
        let start = scriptPubKey.startIndex + 3
        return Data(scriptPubKey[start..<(start + 20)])
    }

    private static func mapParserError(_ err: SwapKitPSBTParserError) -> SwapKitLegacyP2PKHSignerError {
        switch err {
        case .missingPSBT: return .missingPSBT
        case .truncated: return .truncated
        case .invalidMagic: return .invalidMagic
        case .malformed(let reason): return .malformedPSBT(reason: reason)
        }
    }
}

/// Result of parsing the v5 unsigned-tx body. Exposed so tests can pin the
/// structural fields without going through the full PSBT walker.
struct ParsedZcashV5Tx {
    let version: UInt32
    let versionGroupID: UInt32
    let branchID: Data
    let lockTime: UInt32
    let expiryHeight: UInt32
    let inputs: [(prevTxIdLE: Data, prevIndex: UInt32, sequence: UInt32)]
    let outputs: [LegacyP2PKHOutput]
}
