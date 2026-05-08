//
//  BitcoinPsbtSigner.swift
//  VultisigApp
//
//  BIP-143 sighash + signed-tx assembly for the structured `SignBitcoin`
//  PSBT keysign payload. Mirrors the SDK port at
//  vultisig-sdk/packages/core/mpc/keysign/signingInputs/resolvers/bitcoin/sighash.ts
//  and vultisig-sdk/packages/core/mpc/tx/compile/compileSignBitcoinTx.ts.
//
//  Currently supports P2WPKH and P2SH-P2WPKH inputs (SIGHASH_ALL only).
//  P2TR (BIP-341) is intentionally deferred — both the SDK and this port
//  surface a typed error if a `is_ours` input uses an unsupported script.
//

import Foundation
import OSLog
import Tss
import WalletCore

private let logger = Logger(subsystem: "com.vultisig.app", category: "btc-psbt-signer")

enum BitcoinPsbtSignerError: Error, LocalizedError {
    case noInputs
    case noSignableInputs
    case unsupportedScriptType(String)
    case missingRedeemScript(inputIndex: Int)
    case invalidRedeemScript(inputIndex: Int)
    case unsupportedSighashType(UInt32)
    case invalidScriptPubKey(inputIndex: Int)
    case negativeAmount(inputIndex: Int, amount: Int64)
    case missingSignature(sighashHex: String)
    case invalidPublicKey(String)

    var errorDescription: String? {
        switch self {
        case .noInputs:
            return "SignBitcoin has no inputs"
        case .noSignableInputs:
            return "No signable inputs (all isOurs == false)"
        case .unsupportedScriptType(let type):
            return "Unsupported script type for BIP-143 sighash: \(type)"
        case .missingRedeemScript(let i):
            return "Input #\(i): P2SH-P2WPKH inputs require a redeem script"
        case .invalidRedeemScript(let i):
            return "Input #\(i): unsupported redeem script for P2SH-P2WPKH"
        case .unsupportedSighashType(let flag):
            return "Unsupported sighash type: 0x\(String(flag, radix: 16)). Only SIGHASH_ALL is supported."
        case .invalidScriptPubKey(let i):
            return "Input #\(i): invalid scriptPubKey hex"
        case .negativeAmount(let i, let amount):
            return "Input #\(i): amount must be non-negative, got \(amount)"
        case .missingSignature(let hex):
            return "Missing signature for sighash \(hex.prefix(16))..."
        case .invalidPublicKey(let key):
            return "Invalid public key: \(key)"
        }
    }
}

enum BitcoinPsbtSigner {

    // MARK: - Internal helpers (exposed for unit testing of BIP-143 intermediate values).

    static func _hashPrevouts(_ signBitcoin: SignBitcoin) -> Data {
        let data = signBitcoin.inputs.reduce(Data()) { acc, input in
            acc + serializeOutpoint(hash: input.hash, index: input.index)
        }
        return hash256(data)
    }

    static func _hashSequence(_ signBitcoin: SignBitcoin) -> Data {
        let data = signBitcoin.inputs.reduce(Data()) { acc, input in
            acc + writeUInt32LE(input.sequence)
        }
        return hash256(data)
    }

    static func _hashOutputs(_ signBitcoin: SignBitcoin) -> Data {
        let data = signBitcoin.outputs.reduce(Data()) { acc, output in
            let scriptBytes = Data(hexString: output.scriptPubKey) ?? Data()
            return acc + serializeOutput(amount: output.amount, scriptPubKey: scriptBytes)
        }
        return hash256(data)
    }

    // MARK: - Public API

    /// Compute one BIP-143 sighash per `is_ours` input, in input order.
    static func preSigningHashes(_ signBitcoin: SignBitcoin) throws -> [Data] {
        guard !signBitcoin.inputs.isEmpty else {
            throw BitcoinPsbtSignerError.noInputs
        }
        guard signBitcoin.inputs.contains(where: { $0.isOurs }) else {
            throw BitcoinPsbtSignerError.noSignableInputs
        }

        let hashPrevouts = _hashPrevouts(signBitcoin)
        let hashSequence = _hashSequence(signBitcoin)
        let hashOutputs = _hashOutputs(signBitcoin)

        var sighashes: [Data] = []
        for (i, input) in signBitcoin.inputs.enumerated() where input.isOurs {
            let scriptCode = try scriptCode(for: input, inputIndex: i)
            let sighashFlag = input.effectiveSighashType
            let baseType = sighashFlag & 0x1F
            let anyoneCanPay = (sighashFlag & 0x80) != 0
            guard baseType == 0x01, !anyoneCanPay else {
                throw BitcoinPsbtSignerError.unsupportedSighashType(sighashFlag)
            }
            guard input.amount >= 0 else {
                throw BitcoinPsbtSignerError.negativeAmount(inputIndex: i, amount: input.amount)
            }

            // BIP-143 preimage:
            // version || hashPrevouts || hashSequence || outpoint || scriptCode
            //   || value || sequence || hashOutputs || locktime || sighashType
            var preimage = Data()
            preimage.append(writeUInt32LE(signBitcoin.version))
            preimage.append(hashPrevouts)
            preimage.append(hashSequence)
            preimage.append(serializeOutpoint(hash: input.hash, index: input.index))
            preimage.append(scriptCode)
            preimage.append(writeUInt64LE(UInt64(input.amount)))
            preimage.append(writeUInt32LE(input.sequence))
            preimage.append(hashOutputs)
            preimage.append(writeUInt32LE(signBitcoin.locktime))
            preimage.append(writeUInt32LE(sighashFlag))

            sighashes.append(hash256(preimage))
        }
        return sighashes
    }

    /// Assemble a raw signed segwit transaction from `SignBitcoin` + MPC signatures.
    /// Witness layout for P2WPKH and P2SH-P2WPKH: `[der_sig||sighash_flag, pubKey]`.
    static func compileSignedTransaction(
        signBitcoin: SignBitcoin,
        signatures: [String: TssKeysignResponse],
        pubKeyHex: String
    ) throws -> SignedTransactionResult {
        guard let pubKeyData = Data(hexString: pubKeyHex),
              PublicKey(data: pubKeyData, type: .secp256k1) != nil else {
            throw BitcoinPsbtSignerError.invalidPublicKey(pubKeyHex)
        }

        let sighashes = try preSigningHashes(signBitcoin)
        let provider = SignatureProvider(signatures: signatures)

        // Assemble witnesses for `is_ours` inputs first (one signature per
        // sighash, in is_ours order). Non-ours inputs get an empty witness
        // stack — the resulting tx is invalid on-chain if any non-ours inputs
        // exist (matches SDK behavior: multi-party PSBT preservation is a
        // follow-up).
        var witnesses: [[Data]] = Array(repeating: [], count: signBitcoin.inputs.count)
        var sighashIndex = 0
        for (i, input) in signBitcoin.inputs.enumerated() where input.isOurs {
            let sighash = sighashes[sighashIndex]
            sighashIndex += 1

            let derSig = provider.getDerSignature(preHash: sighash)
            guard !derSig.isEmpty else {
                throw BitcoinPsbtSignerError.missingSignature(sighashHex: sighash.hexString)
            }
            var sigPlusFlag = derSig
            sigPlusFlag.append(UInt8(input.effectiveSighashType & 0xFF))
            witnesses[i] = [sigPlusFlag, pubKeyData]
        }

        let rawTx = serializeSegwitTransaction(signBitcoin: signBitcoin, witnesses: witnesses)
        return SignedTransactionResult(
            rawTransaction: rawTx.hexString,
            transactionHash: txid(signBitcoin)
        )
    }

    // MARK: - Sighash helpers

    private static func scriptCode(for input: BitcoinInput, inputIndex: Int) throws -> Data {
        switch input.scriptType.lowercased() {
        case "p2wpkh":
            guard let scriptPubKey = Data(hexString: input.scriptPubKey) else {
                throw BitcoinPsbtSignerError.invalidScriptPubKey(inputIndex: inputIndex)
            }
            return try p2wpkhScriptCode(witnessProgram: scriptPubKey, inputIndex: inputIndex)
        case "p2sh-p2wpkh":
            guard let redeemHex = input.redeemScript else {
                throw BitcoinPsbtSignerError.missingRedeemScript(inputIndex: inputIndex)
            }
            guard let redeemScript = Data(hexString: redeemHex) else {
                throw BitcoinPsbtSignerError.invalidRedeemScript(inputIndex: inputIndex)
            }
            return try p2wpkhScriptCode(witnessProgram: redeemScript, inputIndex: inputIndex)
        default:
            throw BitcoinPsbtSignerError.unsupportedScriptType(input.scriptType)
        }
    }

    /// Derive the BIP-143 scriptCode from a P2WPKH witness program
    /// (`0x00 0x14 <20-byte-hash>`). The leading `0x19` is the script length
    /// per BIP-143, included in the scriptCode itself.
    private static func p2wpkhScriptCode(witnessProgram: Data, inputIndex: Int) throws -> Data {
        guard witnessProgram.count == 22,
              witnessProgram[0] == 0x00,
              witnessProgram[1] == 0x14 else {
            throw BitcoinPsbtSignerError.invalidRedeemScript(inputIndex: inputIndex)
        }
        let pubkeyHash = witnessProgram.subdata(in: 2..<22)
        var scriptCode = Data([0x19, 0x76, 0xa9, 0x14])
        scriptCode.append(pubkeyHash)
        scriptCode.append(contentsOf: [0x88, 0xac])
        return scriptCode
    }

    // MARK: - Tx serialization

    /// Build a segwit transaction (BIP-141 marker+flag, witness stacks).
    /// P2SH-P2WPKH inputs include a scriptSig that pushes the redeem script.
    private static func serializeSegwitTransaction(
        signBitcoin: SignBitcoin,
        witnesses: [[Data]]
    ) -> Data {
        var tx = Data()
        tx.append(writeUInt32LE(signBitcoin.version))
        tx.append(0x00) // marker
        tx.append(0x01) // flag
        tx.append(serializeInputsAndOutputs(signBitcoin))
        for stack in witnesses {
            tx.append(writeVarInt(UInt64(stack.count)))
            for item in stack {
                tx.append(writeVarInt(UInt64(item.count)))
                tx.append(item)
            }
        }
        tx.append(writeUInt32LE(signBitcoin.locktime))
        return tx
    }

    /// Shared input/output serialization (varint counts + per-input scriptSig
    /// + per-output value/script). Excludes version/locktime/witness data so
    /// the same bytes can be reused for both the segwit tx body and the
    /// non-witness txid preimage.
    private static func serializeInputsAndOutputs(_ signBitcoin: SignBitcoin) -> Data {
        var data = Data()
        data.append(writeVarInt(UInt64(signBitcoin.inputs.count)))
        for input in signBitcoin.inputs {
            data.append(serializeOutpoint(hash: input.hash, index: input.index))
            let scriptSig = scriptSig(for: input)
            data.append(writeVarInt(UInt64(scriptSig.count)))
            data.append(scriptSig)
            data.append(writeUInt32LE(input.sequence))
        }
        data.append(writeVarInt(UInt64(signBitcoin.outputs.count)))
        for output in signBitcoin.outputs {
            data.append(writeUInt64LE(UInt64(output.amount)))
            let script = Data(hexString: output.scriptPubKey) ?? Data()
            data.append(writeVarInt(UInt64(script.count)))
            data.append(script)
        }
        return data
    }

    /// scriptSig is empty for native segwit and `<push redeem_script>` for P2SH-P2WPKH.
    private static func scriptSig(for input: BitcoinInput) -> Data {
        guard input.scriptType.lowercased() == "p2sh-p2wpkh",
              let redeemHex = input.redeemScript,
              let redeem = Data(hexString: redeemHex) else {
            return Data()
        }
        var scriptSig = Data()
        scriptSig.append(UInt8(redeem.count & 0xFF))
        scriptSig.append(redeem)
        return scriptSig
    }

    /// txid is double-sha256 of the *non-witness* serialization, displayed in
    /// reverse byte order (Bitcoin convention).
    private static func txid(_ signBitcoin: SignBitcoin) -> String {
        var tx = Data()
        tx.append(writeUInt32LE(signBitcoin.version))
        tx.append(serializeInputsAndOutputs(signBitcoin))
        tx.append(writeUInt32LE(signBitcoin.locktime))
        return Data(hash256(tx).reversed()).hexString
    }
}

// MARK: - Byte helpers

/// Little-endian 4-byte uint.
private func writeUInt32LE(_ value: UInt32) -> Data {
    withUnsafeBytes(of: value.littleEndian) { Data($0) }
}

/// Little-endian 8-byte uint (Bitcoin amounts are unsigned).
private func writeUInt64LE(_ value: UInt64) -> Data {
    withUnsafeBytes(of: value.littleEndian) { Data($0) }
}

/// Bitcoin CompactSize varint encoding.
private func writeVarInt(_ value: UInt64) -> Data {
    if value < 0xFD {
        return Data([UInt8(value)])
    }
    if value <= 0xFFFF {
        var buf = Data([0xFD])
        buf.append(writeUInt32LE(UInt32(value)).prefix(2))
        return buf
    }
    if value <= 0xFFFFFFFF {
        var buf = Data([0xFE])
        buf.append(writeUInt32LE(UInt32(value)))
        return buf
    }
    var buf = Data([0xFF])
    buf.append(writeUInt64LE(value))
    return buf
}

/// Outpoint: txid bytes (display order reversed to internal LE) + 4-byte vout LE.
private func serializeOutpoint(hash: String, index: UInt32) -> Data {
    let txid = Data(hexString: hash) ?? Data()
    var out = Data(txid.reversed())
    out.append(writeUInt32LE(index))
    return out
}

/// Tx output: 8-byte value LE + varint script length + scriptPubKey bytes.
private func serializeOutput(amount: Int64, scriptPubKey: Data) -> Data {
    var out = Data()
    out.append(writeUInt64LE(UInt64(bitPattern: amount)))
    out.append(writeVarInt(UInt64(scriptPubKey.count)))
    out.append(scriptPubKey)
    return out
}

/// double-SHA256 (Bitcoin's hash256).
private func hash256(_ data: Data) -> Data {
    Hash.sha256SHA256(data: data)
}
