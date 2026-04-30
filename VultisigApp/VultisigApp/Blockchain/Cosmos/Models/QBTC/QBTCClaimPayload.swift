//
//  QBTCClaimPayload.swift
//  VultisigApp
//
//  Claim-specific data carried alongside a `KeysignPayload` so that the
//  QBTC helper can build a `MsgClaimWithProof` TxBody instead of the
//  default `MsgSend`. Local-only — not round-tripped through the
//  `commondata` `KeysignPayload` proto for v1. The peer device in a
//  SecureVault flow signs the same hashes; it just won't see "Claim
//  X UTXOs" specifically. Promote to a proto OneOf field if peer-side
//  claim UX matters later.
//

import Foundation

struct QBTCClaimPayload: Codable, Hashable {
    /// Hex-encoded PLONK proof returned by the proof service.
    let proofHex: String
    /// 64-char hex; matches `QBTCClaimHashes.messageHash`.
    let messageHashHex: String
    /// 40-char hex; matches `QBTCClaimHashes.addressHash` (Hash160).
    let addressHashHex: String
    /// 64-char hex; matches `QBTCClaimHashes.qbtcAddressHash`.
    let qbtcAddressHashHex: String
    /// 64-char hex; `SHA256(compressed_btc_pubkey)`. Required by the chain
    /// (`MsgClaimWithProof.pub_key_hash_sha256`, proto field 7) — see
    /// `qbtc/proto/qbtc/qbtc/v1/msg_claim_with_proof.proto:43-46`.
    let pubKeyHashSha256Hex: String
    /// The UTXOs being claimed. `vout = 0` is encoded as proto3 default-skip
    /// downstream — see `QBTCHelper.encodeUtxoRef`.
    let utxos: [ClaimableUtxo]

    /// Adapts to a `QBTCClaimMessage` for the proto encoder by injecting
    /// the claimer (caller-side: typically `keysignPayload.coin.address`).
    func toClaimMessage(claimer: String) -> QBTCClaimMessage {
        QBTCClaimMessage(
            claimer: claimer,
            utxos: utxos,
            proofHex: proofHex,
            messageHashHex: messageHashHex,
            addressHashHex: addressHashHex,
            qbtcAddressHashHex: qbtcAddressHashHex,
            pubKeyHashSha256Hex: pubKeyHashSha256Hex
        )
    }
}
