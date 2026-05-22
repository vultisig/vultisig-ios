//
//  SwapKitTronSigner.swift
//  VultisigApp
//
//  Signs SwapKit's pre-built TRON transaction by hashing `raw_data_hex`
//  directly (the canonical Tron signing input is `sha256(raw_data_bytes)`,
//  which is also the `txID`) and re-assembling a TronWeb-style JSON
//  envelope around the MPC signature.
//
//  Decision: hash-and-sign over the SwapKit `raw_data_hex` bytes verbatim
//  (option B in the consolidated-signing plan). Option A — translate
//  SwapKit's `raw_data` JSON object back into a `TronSigningInput` proto
//  and let WalletCore's `TransactionCompiler` produce the sighash — would
//  re-derive the same digest but only at the cost of reimplementing every
//  `contract.type` SwapKit might emit (`TriggerSmartContract`,
//  `TransferContract`, `TransferAssetContract`, ...). Trusting SwapKit's
//  pre-built `raw_data_hex` keeps the surface area small and gives the
//  cosigning peer identical bytes to verify against.
//
//  Trade-off: SwapKit's `fee_limit` (typically 10 TRX for TRC-20 routes)
//  is baked into `raw_data_hex` and we don't second-guess it here. The
//  Vultisig TRC-20 fee path (PR #4131) runs a constant-contract simulation
//  to compute the right fee_limit when iOS initiates a swap directly; for
//  SwapKit-routed swaps the provider picks the limit. If a swap reverts on
//  OUT_OF_ENERGY, the user retries via a direct Tron route (where the
//  simulation-driven floor kicks in) — we log a warning to surface the
//  signal in support logs.
//

import Foundation
import OSLog
import Tss
import WalletCore

private let logger = Logger(subsystem: "com.vultisig.app", category: "swapkit-tron-signer")

enum SwapKitTronSignerError: Error, LocalizedError {
    case emptyPayload
    case invalidJSON
    case missingRawDataHex
    case invalidRawDataHex
    case missingSignature(digestHex: String)
    case invalidPublicKey(String)
    case signatureVerifyFailed
    case envelopeEncodeFailed

    var errorDescription: String? {
        switch self {
        case .emptyPayload:
            return "SwapKit TRON payload is empty"
        case .invalidJSON:
            return "SwapKit TRON payload is not valid JSON"
        case .missingRawDataHex:
            return "SwapKit TRON payload is missing raw_data_hex"
        case .invalidRawDataHex:
            return "SwapKit TRON raw_data_hex is not valid hex"
        case .missingSignature(let hex):
            return "MPC signature missing for Tron digest \(hex.prefix(16))..."
        case .invalidPublicKey(let key):
            return "Invalid Tron public key: \(key)"
        case .signatureVerifyFailed:
            return "SwapKit TRON signature verification failed"
        case .envelopeEncodeFailed:
            return "Failed to encode signed TronWeb envelope"
        }
    }
}

enum SwapKitTronSigner {

    /// Compute Tron's signing digest = `sha256(raw_data_bytes)`. Single hash
    /// per transaction, hex-encoded to match the keysign message-hash
    /// convention.
    static func preSigningHashes(payload: SwapKitSwapPayload) throws -> [String] {
        let digest = try digest(payload: payload)
        return [digest.hexString]
    }

    /// Assemble the broadcast-format TronWeb envelope from SwapKit's
    /// `raw_data` + `raw_data_hex` + `txID` and the MPC ECDSA signature.
    /// `rawTransaction` is the JSON string the `TronService.broadcastTransaction`
    /// caller posts to `/wallet/broadcasttransaction`.
    static func compileSignedTransaction(
        payload: SwapKitSwapPayload,
        signatures: [String: TssKeysignResponse],
        pubKeyHex: String
    ) throws -> SignedTransactionResult {
        guard let pubKeyData = Data(hexString: pubKeyHex),
              let secp = PublicKey(data: pubKeyData, type: .secp256k1Extended) else {
            throw SwapKitTronSignerError.invalidPublicKey(pubKeyHex)
        }
        let publicKey = secp.uncompressed

        let parsed = try parsePayload(payload.txPayload)
        let rawDataBytes = parsed.rawDataBytes
        let digest = Hash.sha256(data: rawDataBytes)

        let provider = SignatureProvider(signatures: signatures)
        let signature = provider.getSignatureWithRecoveryID(preHash: digest)
        guard signature.count == 65 else {
            throw SwapKitTronSignerError.missingSignature(digestHex: digest.hexString)
        }
        guard publicKey.verify(signature: signature, message: digest) else {
            throw SwapKitTronSignerError.signatureVerifyFailed
        }

        // Log when SwapKit's fee_limit looks suspiciously low so post-mortem
        // logs catch OUT_OF_ENERGY reverts in production. We don't fail the
        // sign — the user might still have enough staked energy to cover the
        // call even with a tight fee_limit.
        if let feeLimit = parsed.feeLimit, feeLimit > 0, feeLimit < 20_000_000 {
            logger.warning(
                "SwapKit TRON fee_limit looks tight: \(feeLimit, privacy: .public) sun"
            )
        }

        let envelope: Data
        do {
            envelope = try makeBroadcastEnvelope(
                rawJSON: payload.txPayload,
                signatureHex: signature.hexString
            )
        } catch {
            logger.error("Failed to build SwapKit TRON broadcast envelope: \(error.localizedDescription, privacy: .public)")
            throw SwapKitTronSignerError.envelopeEncodeFailed
        }

        guard let envelopeString = String(data: envelope, encoding: .utf8) else {
            throw SwapKitTronSignerError.envelopeEncodeFailed
        }
        return SignedTransactionResult(
            rawTransaction: envelopeString,
            transactionHash: digest.hexString
        )
    }

    /// Tron signing digest = `sha256(raw_data_bytes)`. Exposed for unit
    /// tests so the digest can be pinned to the SwapKit-reported `txID`
    /// (Tron's txID is exactly this digest).
    static func digest(payload: SwapKitSwapPayload) throws -> Data {
        let parsed = try parsePayload(payload.txPayload)
        return Hash.sha256(data: parsed.rawDataBytes)
    }

    // MARK: - Wire helpers

    private struct ParsedPayload {
        let rawDataBytes: Data
        let feeLimit: Int64?
        let object: [String: Any]
    }

    private static func parsePayload(_ bytes: Data) throws -> ParsedPayload {
        guard !bytes.isEmpty else { throw SwapKitTronSignerError.emptyPayload }
        guard let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] else {
            throw SwapKitTronSignerError.invalidJSON
        }
        guard let rawDataHex = object["raw_data_hex"] as? String else {
            throw SwapKitTronSignerError.missingRawDataHex
        }
        guard let rawDataBytes = Data(hexString: rawDataHex) else {
            throw SwapKitTronSignerError.invalidRawDataHex
        }
        let rawData = object["raw_data"] as? [String: Any]
        let feeLimit: Int64?
        if let fl = rawData?["fee_limit"] as? Int64 {
            feeLimit = fl
        } else if let fl = rawData?["fee_limit"] as? Int {
            feeLimit = Int64(fl)
        } else if let fl = rawData?["fee_limit"] as? NSNumber {
            feeLimit = fl.int64Value
        } else {
            feeLimit = nil
        }
        return ParsedPayload(rawDataBytes: rawDataBytes, feeLimit: feeLimit, object: object)
    }

    /// Build the TronWeb broadcast envelope from SwapKit's pre-built tx
    /// object plus the signature hex. We re-encode the canonical fields
    /// (`txID`, `raw_data`, `raw_data_hex`, `visible`) verbatim and append
    /// `signature: [hex]`.
    private static func makeBroadcastEnvelope(
        rawJSON: Data,
        signatureHex: String
    ) throws -> Data {
        guard var object = try? JSONSerialization.jsonObject(with: rawJSON) as? [String: Any] else {
            throw SwapKitTronSignerError.invalidJSON
        }
        object["signature"] = [signatureHex]
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
