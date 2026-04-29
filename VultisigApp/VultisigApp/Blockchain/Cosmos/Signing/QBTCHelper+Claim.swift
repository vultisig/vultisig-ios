//
//  QBTCHelper+Claim.swift
//  VultisigApp
//
//  Protobuf encoding for MsgClaimWithProof, TxBody, AuthInfo, SignDoc,
//  and TxRaw. Mirrors vultisig-sdk/.../buildClaimTx.ts and
//  vultisig-windows/.../buildClaimSignDoc.ts byte-for-byte. Reuses the
//  appendProto* helpers from QBTCHelper.swift, which already match the
//  SDK's proto3 default-skip behaviour (skip zero varints, skip empty
//  strings/bytes).
//

import CryptoSwift
import Foundation

/// Inputs needed to assemble a `MsgClaimWithProof` cosmos message.
struct QBTCClaimMessage {
    let claimer: String
    let utxos: [ClaimableUtxo]
    /// Hex-encoded PLONK ZK proof.
    let proofHex: String
    /// 64 hex chars.
    let messageHashHex: String
    /// 40 hex chars.
    let addressHashHex: String
    /// 64 hex chars.
    let qbtcAddressHashHex: String
}

enum QBTCClaimMessageError: LocalizedError {
    case utxoCountOutOfRange(Int)
    case invalidTxid(String)
    case duplicateUtxo(txid: String, vout: UInt32)
    case proofTooSmall(hexLength: Int)
    case proofTooLarge(hexLength: Int)
    case invalidHexField(name: String, expectedLength: Int, got: Int)

    var errorDescription: String? {
        switch self {
        case .utxoCountOutOfRange(let count):
            return "UTXOs count must be 1-\(QBTCClaimConfig.maxClaimUtxos), got \(count)"
        case .invalidTxid(let txid):
            return "Invalid txid: expected 64 hex chars, got \(txid.count)"
        case .duplicateUtxo(let txid, let vout):
            return "Duplicate UTXO reference: \(txid):\(vout)"
        case .proofTooSmall(let len):
            return "Proof too small or not valid hex (min 100 bytes / 200 hex chars), got \(len)"
        case .proofTooLarge(let len):
            return "Proof too large (max 50 KB / 100000 hex chars), got \(len)"
        case .invalidHexField(let name, let expected, let got):
            return "\(name) must be \(expected) hex chars, got \(got)"
        }
    }
}

extension QBTCHelper {
    /// Validates the claim input against the chain's constraints. See
    /// `vultisig-sdk/.../buildClaimTx.ts:41-72`.
    static func validateClaimInput(_ input: QBTCClaimMessage) throws {
        let count = input.utxos.count
        guard count >= 1, count <= QBTCClaimConfig.maxClaimUtxos else {
            throw QBTCClaimMessageError.utxoCountOutOfRange(count)
        }

        var seen = Set<String>()
        for utxo in input.utxos {
            guard utxo.txid.count == 64, isHex(utxo.txid) else {
                throw QBTCClaimMessageError.invalidTxid(utxo.txid)
            }
            let key = "\(utxo.txid):\(utxo.vout)"
            if !seen.insert(key).inserted {
                throw QBTCClaimMessageError.duplicateUtxo(txid: utxo.txid, vout: utxo.vout)
            }
        }

        guard isHex(input.proofHex) else {
            throw QBTCClaimMessageError.proofTooSmall(hexLength: input.proofHex.count)
        }
        guard input.proofHex.count >= 200 else {
            throw QBTCClaimMessageError.proofTooSmall(hexLength: input.proofHex.count)
        }
        guard input.proofHex.count <= 100_000 else {
            throw QBTCClaimMessageError.proofTooLarge(hexLength: input.proofHex.count)
        }

        try assertHex(input.messageHashHex, name: "message_hash", expected: 64)
        try assertHex(input.addressHashHex, name: "address_hash", expected: 40)
        try assertHex(input.qbtcAddressHashHex, name: "qbtc_address_hash", expected: 64)
    }

    /// Encodes a single `UTXORef` as protobuf bytes:
    /// `{ string txid = 1; uint32 vout = 2; }`. When `vout == 0` the field
    /// is omitted (proto3 default-skip) — the chain accepts this.
    static func encodeUtxoRef(_ utxo: ClaimableUtxo) -> Data {
        var data = Data()
        data.appendProtoString(fieldNumber: 1, value: utxo.txid)
        data.appendProtoVarint(fieldNumber: 2, value: UInt64(utxo.vout))
        return data
    }

    /// Encodes the full `MsgClaimWithProof` message body in field-number
    /// order. Repeated `utxos (2)` are emitted as separate length-delimited
    /// records, NOT packed.
    static func encodeMsgClaimWithProof(_ input: QBTCClaimMessage) -> Data {
        var msg = Data()
        msg.appendProtoString(fieldNumber: 1, value: input.claimer)
        for utxo in input.utxos {
            msg.appendProtoBytes(fieldNumber: 2, data: encodeUtxoRef(utxo))
        }
        msg.appendProtoString(fieldNumber: 3, value: input.proofHex)
        msg.appendProtoString(fieldNumber: 4, value: input.messageHashHex)
        msg.appendProtoString(fieldNumber: 5, value: input.addressHashHex)
        msg.appendProtoString(fieldNumber: 6, value: input.qbtcAddressHashHex)
        return msg
    }

    /// Wraps `MsgClaimWithProof` in a `cosmos.base.Any` (typeURL + value).
    static func buildClaimWithProofAny(_ input: QBTCClaimMessage) throws -> Data {
        try validateClaimInput(input)
        let msg = encodeMsgClaimWithProof(input)
        var anyMsg = Data()
        anyMsg.appendProtoString(fieldNumber: 1, value: QBTCClaimConfig.msgClaimWithProofTypeURL)
        anyMsg.appendProtoBytes(fieldNumber: 2, data: msg)
        return anyMsg
    }

    /// Builds the cosmos `TxBody` containing a single `MsgClaimWithProof`.
    /// No memo is encoded for claim transactions.
    static func buildClaimTxBody(_ input: QBTCClaimMessage) throws -> Data {
        let anyMsg = try buildClaimWithProofAny(input)
        var txBody = Data()
        txBody.appendProtoBytes(fieldNumber: 1, data: anyMsg)
        return txBody
    }

    // MARK: - SignDoc / TxRaw assembly
    //
    // Mirrors vultisig-windows/.../buildClaimSignDoc.ts. The claim tx is
    // gas-free: AuthInfo encodes only `gas_limit`, no fee coins. A single
    // MLDSA signer (the claimer) authenticates the cosmos transaction;
    // BTC ownership is proven by the ZK proof inside the message body.

    /// Encodes `cosmos.tx.v1beta1.AuthInfo` for a claim. Single MLDSA
    /// signer (`/cosmos.crypto.mldsa.PubKey`) in SIGN_MODE_DIRECT. Fee
    /// contains only `gas_limit` (no `amount` coins, no `payer`).
    static func buildClaimAuthInfo(mldsaPublicKey: Data, sequence: UInt64) -> Data {
        // PubKey message: field 1 = key (bytes)
        var pubKeyMsg = Data()
        pubKeyMsg.appendProtoBytes(fieldNumber: 1, data: mldsaPublicKey)

        // Any wrapping the PubKey
        var pubKeyAny = Data()
        pubKeyAny.appendProtoString(fieldNumber: 1, value: QBTCClaimConfig.mldsaPubKeyTypeURL)
        pubKeyAny.appendProtoBytes(fieldNumber: 2, data: pubKeyMsg)

        // ModeInfo.Single: SIGN_MODE_DIRECT = 1
        var singleMode = Data()
        singleMode.appendProtoVarint(fieldNumber: 1, value: 1)

        var modeInfo = Data()
        modeInfo.appendProtoBytes(fieldNumber: 1, data: singleMode)

        // SignerInfo: field 1 = public_key, field 2 = mode_info, field 3 = sequence
        var signerInfo = Data()
        signerInfo.appendProtoBytes(fieldNumber: 1, data: pubKeyAny)
        signerInfo.appendProtoBytes(fieldNumber: 2, data: modeInfo)
        signerInfo.appendProtoVarint(fieldNumber: 3, value: sequence)

        // Fee: field 1 = amount (NONE — gas-free claim), field 2 = gas_limit
        var fee = Data()
        fee.appendProtoVarint(fieldNumber: 2, value: QBTCClaimConfig.gasLimit)

        // AuthInfo: field 1 = signer_infos (repeated), field 2 = fee
        var authInfo = Data()
        authInfo.appendProtoBytes(fieldNumber: 1, data: signerInfo)
        authInfo.appendProtoBytes(fieldNumber: 2, data: fee)
        return authInfo
    }

    /// Result of `buildClaimSignDoc` — the artifacts the orchestrator
    /// threads forward into the MLDSA round and the broadcast step.
    struct ClaimSignDocArtifacts: Equatable {
        let authInfoBytes: Data
        let signDocBytes: Data
        /// Lowercased hex of `SHA256(signDocBytes)`. This is the exact
        /// string the MLDSA TSS keysign signs and the key the iOS
        /// `DilithiumKeysign` result is looked up by — keep formatting
        /// identical at both sites.
        let signDocHashHex: String
    }

    /// Builds the SignDoc and computes its SHA-256. Convenience wrapper
    /// around `buildClaimAuthInfo` + cosmos `SignDoc` (fields 1..4).
    /// Defaults to `QBTCClaimConfig.chainId` so callers don't drift.
    static func buildClaimSignDoc(
        bodyBytes: Data,
        mldsaPublicKey: Data,
        accountNumber: UInt64,
        sequence: UInt64,
        chainId: String = QBTCClaimConfig.chainId
    ) -> ClaimSignDocArtifacts {
        let authInfoBytes = buildClaimAuthInfo(mldsaPublicKey: mldsaPublicKey, sequence: sequence)

        // SignDoc: field 1 = body_bytes, field 2 = auth_info_bytes,
        // field 3 = chain_id, field 4 = account_number.
        var signDoc = Data()
        signDoc.appendProtoBytes(fieldNumber: 1, data: bodyBytes)
        signDoc.appendProtoBytes(fieldNumber: 2, data: authInfoBytes)
        signDoc.appendProtoString(fieldNumber: 3, value: chainId)
        signDoc.appendProtoVarint(fieldNumber: 4, value: accountNumber)

        let hashHex = signDoc.sha256().toHexString()
        return ClaimSignDocArtifacts(
            authInfoBytes: authInfoBytes,
            signDocBytes: signDoc,
            signDocHashHex: hashHex
        )
    }

    /// Result of `assembleClaimTxRaw`. `txHashHex` is uppercased to
    /// match the SDK and the windows app (their tx-hash links use
    /// uppercase hex).
    struct ClaimTxRawArtifacts: Equatable {
        let txRawBytes: Data
        let txHashHex: String
    }

    /// Wraps the body, auth info, and MLDSA signature into a
    /// `cosmos.tx.v1beta1.TxRaw` and computes its SHA-256 hash locally.
    /// The chain accepts the broadcast as idempotent on retry by hash.
    static func assembleClaimTxRaw(
        bodyBytes: Data,
        authInfoBytes: Data,
        mldsaSignature: Data
    ) -> ClaimTxRawArtifacts {
        // TxRaw: field 1 = body_bytes, field 2 = auth_info_bytes,
        // field 3 = signatures (repeated bytes; one entry).
        var txRaw = Data()
        txRaw.appendProtoBytes(fieldNumber: 1, data: bodyBytes)
        txRaw.appendProtoBytes(fieldNumber: 2, data: authInfoBytes)
        txRaw.appendProtoBytes(fieldNumber: 3, data: mldsaSignature)

        let hashHex = txRaw.sha256().toHexString().uppercased()
        return ClaimTxRawArtifacts(txRawBytes: txRaw, txHashHex: hashHex)
    }

    // MARK: - Hex helpers (file-private)

    private static func isHex(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        return value.allSatisfy { $0.isHexDigit }
    }

    private static func assertHex(_ value: String, name: String, expected: Int) throws {
        guard value.count == expected, isHex(value) else {
            throw QBTCClaimMessageError.invalidHexField(name: name, expectedLength: expected, got: value.count)
        }
    }
}
