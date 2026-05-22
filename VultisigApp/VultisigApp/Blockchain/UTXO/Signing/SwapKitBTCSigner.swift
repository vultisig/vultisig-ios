//
//  SwapKitBTCSigner.swift
//  VultisigApp
//
//  Bridges SwapKit's pre-built BTC PSBT payload onto the existing
//  `BitcoinPsbtSigner` (BIP-143) pipeline. SwapKit returns a base64-encoded
//  BIP-174 PSBT — we decode it into the structured `SignBitcoin`
//  representation iOS already uses for dApp PSBT co-signing, then hand it
//  to the canonical sighash + signed-tx assembly path.
//
//  Scope: P2WPKH + P2SH-P2WPKH inputs (matches what `BitcoinPsbtSigner`
//  supports). The Phase 0 SwapKit BTC fixtures (NEAR, GARDEN, FLASHNET) all
//  return single-script-type PSBTs whose inputs are owned by the user's
//  source address — every input is `is_ours = true`.
//
//  PSBT framing primitives (`PSBTCursor`, `readMap`, byte-cursor helpers)
//  live in `SwapKitPSBTParser` so DOGE / BCH / DASH / ZEC signers share the
//  same wire-level decoder. The BTC unsigned-tx body parser stays here —
//  it's BIP-144-shaped, distinct from ZEC's Sapling-v4 body.
//

import Foundation
import OSLog
import Tss

private let logger = Logger(subsystem: "com.vultisig.app", category: "swapkit-btc-signer")

enum SwapKitBTCSignerError: Error, LocalizedError {
    case missingPSBT
    case truncated
    case invalidMagic
    case missingUnsignedTx
    case unsupportedScript(String)
    case missingWitnessUtxo(inputIndex: Int)
    case underlying(BitcoinPsbtSignerError)

    var errorDescription: String? {
        switch self {
        case .missingPSBT:
            return "SwapKit BTC payload has no PSBT bytes"
        case .truncated:
            return "SwapKit BTC PSBT is truncated"
        case .invalidMagic:
            return "SwapKit BTC PSBT magic bytes are invalid"
        case .missingUnsignedTx:
            return "SwapKit BTC PSBT is missing the unsigned-tx global record"
        case .unsupportedScript(let detail):
            return "SwapKit BTC PSBT script not supported: \(detail)"
        case .missingWitnessUtxo(let i):
            return "SwapKit BTC PSBT input #\(i) is missing PSBT_IN_WITNESS_UTXO"
        case .underlying(let err):
            return err.errorDescription
        }
    }
}

enum SwapKitBTCSigner {

    // MARK: - Public dispatcher entrypoints

    /// Compute BIP-143 sighashes for every signable input in the SwapKit PSBT.
    static func preSigningHashes(payload: SwapKitSwapPayload) throws -> [String] {
        let signBitcoin = try decodeToSignBitcoin(psbtBytes: payload.txPayload)
        do {
            return try BitcoinPsbtSigner.preSigningHashes(signBitcoin)
                .map { $0.hexString }
                .sorted()
        } catch let err as BitcoinPsbtSignerError {
            throw SwapKitBTCSignerError.underlying(err)
        }
    }

    /// Assemble the signed segwit transaction from SwapKit's PSBT bytes and
    /// the MPC signatures keyed by sighash hex.
    static func compileSignedTransaction(
        payload: SwapKitSwapPayload,
        signatures: [String: TssKeysignResponse],
        pubKeyHex: String
    ) throws -> SignedTransactionResult {
        let signBitcoin = try decodeToSignBitcoin(psbtBytes: payload.txPayload)
        do {
            return try BitcoinPsbtSigner.compileSignedTransaction(
                signBitcoin: signBitcoin,
                signatures: signatures,
                pubKeyHex: pubKeyHex
            )
        } catch let err as BitcoinPsbtSignerError {
            throw SwapKitBTCSignerError.underlying(err)
        }
    }

    // MARK: - PSBT → SignBitcoin

    /// Decode a BIP-174 PSBT byte blob into the structured `SignBitcoin`
    /// representation. Every input is marked `is_ours = true` — SwapKit only
    /// puts the user's UTXOs in the PSBT inputs, so the assumption holds for
    /// every observed provider (NEAR Intents, Garden, Flashnet).
    static func decodeToSignBitcoin(psbtBytes: Data) throws -> SignBitcoin {
        let (framing, parsedTx) = try parseEnvelope(psbtBytes: psbtBytes)

        var inputs: [BitcoinInput] = []
        for (index, txin) in parsedTx.inputs.enumerated() {
            let input = try makeBitcoinInput(
                inputMap: framing.inputMaps[index],
                index: index,
                txInput: txin
            )
            inputs.append(input)
        }

        var outputs: [BitcoinOutput] = []
        for txout in parsedTx.outputs {
            outputs.append(BitcoinOutput(
                amount: txout.amount,
                address: "",
                opReturnData: nil,
                scriptPubKey: txout.scriptPubKey.hexString,
                isChange: false
            ))
        }

        return SignBitcoin(
            version: parsedTx.version,
            locktime: parsedTx.locktime,
            inputs: inputs,
            outputs: outputs
        )
    }

    /// Parses PSBT framing + the BIP-144 unsigned-tx body. Wraps the shared
    /// `SwapKitPSBTParser` errors into BTC-specific cases so call sites
    /// surface typed errors as before the refactor.
    private static func parseEnvelope(psbtBytes: Data) throws -> (ParsedPSBT, ParsedTx) {
        // Two-phase parse: read the framing header + globals to extract the
        // unsigned-tx bytes, count inputs/outputs from the body, then drain
        // the input/output maps. This lets the BTC-specific body parser
        // drive how many maps to read off the cursor.
        let framingPrefix: (cursor: PSBTCursor, globals: [Data: Data], unsignedTxBytes: Data)
        do {
            framingPrefix = try SwapKitPSBTParser.parseFraming(psbtBytes: psbtBytes)
        } catch let err as SwapKitPSBTParserError {
            throw mapParserError(err)
        }
        let parsedTx: ParsedTx
        do {
            parsedTx = try parseUnsignedTx(framingPrefix.unsignedTxBytes)
        } catch let err as SwapKitPSBTParserError {
            throw mapParserError(err)
        }
        var cursor = framingPrefix.cursor
        var inputMaps: [[Data: Data]] = []
        for _ in 0..<parsedTx.inputs.count {
            do {
                inputMaps.append(try cursor.readMap())
            } catch let err as SwapKitPSBTParserError {
                throw mapParserError(err)
            }
        }
        var outputMaps: [[Data: Data]] = []
        for _ in 0..<parsedTx.outputs.count {
            do {
                outputMaps.append(try cursor.readMap())
            } catch let err as SwapKitPSBTParserError {
                throw mapParserError(err)
            }
        }
        let framing = ParsedPSBT(
            globals: framingPrefix.globals,
            unsignedTxBytes: framingPrefix.unsignedTxBytes,
            inputMaps: inputMaps,
            outputMaps: outputMaps
        )
        return (framing, parsedTx)
    }

    private static func mapParserError(_ err: SwapKitPSBTParserError) -> SwapKitBTCSignerError {
        switch err {
        case .missingPSBT: return .missingPSBT
        case .truncated: return .truncated
        case .invalidMagic: return .invalidMagic
        }
    }

    // MARK: - Per-input materialization

    private static func makeBitcoinInput(
        inputMap: [Data: Data],
        index: Int,
        txInput: ParsedTxInput
    ) throws -> BitcoinInput {
        // SwapKit's PSBT carries each user UTXO as PSBT_IN_WITNESS_UTXO
        // (key type 0x01). The 8-byte LE amount + varint-prefixed
        // scriptPubKey lives in the value.
        guard let witnessUtxo = inputMap[Data([0x01])] else {
            throw SwapKitBTCSignerError.missingWitnessUtxo(inputIndex: index)
        }
        let (amount, scriptPubKey) = try parseWitnessUtxo(witnessUtxo, inputIndex: index)
        let (scriptType, redeemScript) = try classifyScript(
            scriptPubKey: scriptPubKey,
            inputMap: inputMap,
            inputIndex: index
        )
        let sighashTypeBytes = inputMap[Data([0x03])]
        let sighashType: UInt32
        if let bytes = sighashTypeBytes {
            guard bytes.count == 4 else {
                throw SwapKitBTCSignerError.unsupportedScript("sighash-type record has \(bytes.count) bytes, expected 4")
            }
            sighashType = bytes.withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        } else {
            sighashType = 0
        }
        return BitcoinInput(
            hash: txInput.prevTxId,
            index: txInput.prevIndex,
            amount: amount,
            scriptPubKey: scriptPubKey.hexString,
            scriptType: scriptType,
            sighashType: sighashType,
            isOurs: true,
            redeemScript: redeemScript,
            sequence: txInput.sequence
        )
    }

    /// SwapKit's BTC PSBTs in the Phase 0 spike are all P2WPKH; we also
    /// accept P2SH-P2WPKH if `PSBT_IN_REDEEM_SCRIPT` is populated. Anything
    /// else (P2TR, multisig, bare P2PKH, P2WSH) throws — `BitcoinPsbtSigner`
    /// doesn't sign those.
    private static func classifyScript(
        scriptPubKey: Data,
        inputMap: [Data: Data],
        inputIndex: Int
    ) throws -> (scriptType: String, redeemScript: String?) {
        // P2WPKH: 0x00 0x14 <20-byte-hash> (22 bytes total).
        if scriptPubKey.count == 22, scriptPubKey[0] == 0x00, scriptPubKey[1] == 0x14 {
            return ("p2wpkh", nil)
        }
        // P2SH: 0xa9 0x14 <20-byte-hash> 0x87 (23 bytes total). Promotion to
        // P2SH-P2WPKH requires PSBT_IN_REDEEM_SCRIPT (key type 0x04).
        if scriptPubKey.count == 23,
           scriptPubKey[0] == 0xa9,
           scriptPubKey[1] == 0x14,
           scriptPubKey[22] == 0x87 {
            guard let redeem = inputMap[Data([0x04])] else {
                throw SwapKitBTCSignerError.unsupportedScript(
                    "P2SH input #\(inputIndex) missing redeem script"
                )
            }
            // The redeem script for P2SH-P2WPKH is itself a 22-byte
            // witness-v0 program `0x00 0x14 <20-byte-hash>`.
            guard redeem.count == 22, redeem[0] == 0x00, redeem[1] == 0x14 else {
                throw SwapKitBTCSignerError.unsupportedScript(
                    "P2SH redeem script on input #\(inputIndex) is not P2SH-P2WPKH"
                )
            }
            return ("p2sh-p2wpkh", redeem.hexString)
        }
        throw SwapKitBTCSignerError.unsupportedScript(
            "input #\(inputIndex) scriptPubKey is not P2WPKH or P2SH-P2WPKH: \(scriptPubKey.hexString)"
        )
    }

    private static func parseWitnessUtxo(
        _ data: Data,
        inputIndex: Int
    ) throws -> (amount: Int64, scriptPubKey: Data) {
        var c = PSBTCursor(data: data)
        let amountUnsigned: UInt64
        let scriptLen: UInt64
        let script: Data
        do {
            amountUnsigned = try c.readUInt64LE()
            scriptLen = try c.readCompactSize()
            script = try c.readBytes(Int(scriptLen))
        } catch let err as SwapKitPSBTParserError {
            throw mapParserError(err)
        }
        guard c.isAtEnd else {
            throw SwapKitBTCSignerError.unsupportedScript(
                "input #\(inputIndex) WITNESS_UTXO has trailing bytes"
            )
        }
        return (Int64(bitPattern: amountUnsigned), script)
    }

    // MARK: - Unsigned-tx parser (BIP-144 segwit body)

    private struct ParsedTxInput {
        let prevTxId: String
        let prevIndex: UInt32
        let sequence: UInt32
    }
    private struct ParsedTxOutput {
        let amount: Int64
        let scriptPubKey: Data
    }
    private struct ParsedTx {
        let version: UInt32
        let locktime: UInt32
        let inputs: [ParsedTxInput]
        let outputs: [ParsedTxOutput]
    }

    private static func parseUnsignedTx(_ data: Data) throws -> ParsedTx {
        var c = PSBTCursor(data: data)
        let version = try c.readUInt32LE()
        let inputCount = try c.readCompactSize()
        var inputs: [ParsedTxInput] = []
        for _ in 0..<inputCount {
            let prevBytes = try c.readBytes(32)
            // Outpoint hash is stored in internal (little-endian) order on the
            // wire; the SignBitcoin/BIP-143 contract expects big-endian
            // display order. Reverse here once, in one place.
            let prevTxId = Data(prevBytes.reversed()).hexString
            let prevIndex = try c.readUInt32LE()
            // Unsigned txs always have empty scriptSig — we still consume
            // its length-prefixed body for parser correctness.
            let scriptSigLen = try c.readCompactSize()
            _ = try c.readBytes(Int(scriptSigLen))
            let sequence = try c.readUInt32LE()
            inputs.append(ParsedTxInput(
                prevTxId: prevTxId,
                prevIndex: prevIndex,
                sequence: sequence
            ))
        }
        let outputCount = try c.readCompactSize()
        var outputs: [ParsedTxOutput] = []
        for _ in 0..<outputCount {
            let amountUnsigned = try c.readUInt64LE()
            let amount = Int64(bitPattern: amountUnsigned)
            let scriptLen = try c.readCompactSize()
            let script = try c.readBytes(Int(scriptLen))
            outputs.append(ParsedTxOutput(amount: amount, scriptPubKey: script))
        }
        let locktime = try c.readUInt32LE()
        return ParsedTx(version: version, locktime: locktime, inputs: inputs, outputs: outputs)
    }
}
