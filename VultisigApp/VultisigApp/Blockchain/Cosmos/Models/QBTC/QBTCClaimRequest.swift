//
//  QBTCClaimRequest.swift
//  VultisigApp
//
//  Wire-shape DTOs for the QBTC proof service. Field names match the
//  service's snake_case JSON via explicit CodingKeys.
//  Mirrors vultisig-sdk/.../proofService.ts.
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "qbtc-claim-request")

/// One UTXO reference in the `/prove` request — `txid` + `vout` only,
/// no amount (the chain doesn't need amount; that's BTC-side data for UI).
struct ClaimProofUtxoRef: Codable, Equatable {
    let txid: String
    let vout: UInt32
}

extension ClaimProofUtxoRef {
    init(_ utxo: ClaimableUtxo) {
        self.init(txid: utxo.txid, vout: utxo.vout)
    }
}

/// Request body for `POST /prove`. The two ECDSA signature components
/// are zero-padded on the left to fixed widths the prover circuit expects:
/// `signature_r` to 24 bytes, `signature_s` to 32 bytes. Get this wrong
/// and the proof silently fails — see `QBTCClaimConfig.proofServiceRBytes`.
struct ClaimProofRequest: Codable, Equatable {
    let signatureR: String
    let signatureS: String
    let publicKey: String
    let utxos: [ClaimProofUtxoRef]
    let claimerAddress: String
    let chainId: String

    enum CodingKeys: String, CodingKey {
        case signatureR = "signature_r"
        case signatureS = "signature_s"
        case publicKey = "public_key"
        case utxos
        case claimerAddress = "claimer_address"
        case chainId = "chain_id"
    }
}

extension ClaimProofRequest {
    /// Constructs a request from raw signature components, padding them
    /// to the widths the prover expects.
    init(
        rHex: String,
        sHex: String,
        compressedPubkeyHex: String,
        utxos: [ClaimableUtxo],
        claimerAddress: String,
        chainId: String
    ) {
        self.init(
            signatureR: ClaimProofRequest.padSigHex(rHex, byteLength: QBTCClaimConfig.proofServiceRBytes),
            signatureS: ClaimProofRequest.padSigHex(sHex, byteLength: QBTCClaimConfig.proofServiceSBytes),
            publicKey: compressedPubkeyHex,
            utxos: utxos.map(ClaimProofUtxoRef.init),
            claimerAddress: claimerAddress,
            chainId: chainId
        )
    }

    /// Zero-pads a hex string on the LEFT to a fixed byte width (1 byte = 2 hex chars).
    ///
    /// The `r` component on secp256k1 is 32 bytes (64 hex chars), but the prover circuit
    /// declares a 24-byte width for `signature_r`. The prover treats the value as a
    /// fixed-width integer, so the extra eight high bytes are interpreted as leading zeros
    /// of a wider integer — sending the full 32-byte form is what `vultisig-windows` does
    /// and what the proof service expects in practice. We pass the input through unchanged
    /// when it exceeds the target rather than trying to slice it (which would corrupt a
    /// real signature) and let the proof service decide. We log a warning so the case is
    /// visible in Console.app if a failure ever traces back here.
    static func padSigHex(_ hex: String, byteLength: Int) -> String {
        let target = byteLength * 2
        guard hex.count <= target else {
            logger.warning("padSigHex: \(hex.count)-char hex exceeds target \(target) (byteLength=\(byteLength)); forwarding untruncated — matches vultisig-windows.")
            return hex
        }
        let padded = hex.count < target
            ? String(repeating: "0", count: target - hex.count) + hex
            : hex
        assert(padded.count == target, "padded sig must be \(target) hex chars, got \(padded.count)")
        return padded
    }
}

/// Response from `POST /prove`. The hashes are returned for the caller
/// to feed into `MsgClaimWithProof` — no recomputation required.
struct ClaimProofResponse: Codable, Equatable {
    let proof: String
    let messageHash: String
    let addressHash: String
    let qbtcAddressHash: String
    let utxos: [ClaimProofUtxoRef]
    let claimerAddress: String

    enum CodingKeys: String, CodingKey {
        case proof
        case messageHash = "message_hash"
        case addressHash = "address_hash"
        case qbtcAddressHash = "qbtc_address_hash"
        case utxos
        case claimerAddress = "claimer_address"
    }
}

/// Response from `GET /health`. Both fields must be `"healthy"` and
/// `true` respectively for the service to be considered usable.
struct ProofServiceHealth: Codable, Equatable {
    let status: String
    let setupLoaded: Bool

    enum CodingKeys: String, CodingKey {
        case status
        case setupLoaded = "setup_loaded"
    }

    var isHealthy: Bool {
        status.lowercased() == "healthy" && setupLoaded
    }
}
