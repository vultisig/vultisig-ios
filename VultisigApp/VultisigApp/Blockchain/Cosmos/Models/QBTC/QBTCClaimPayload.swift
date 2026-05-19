//
//  QBTCClaimPayload.swift
//  VultisigApp
//
//  Legacy carrier for QBTC claim data on `KeysignPayload`. Retained as a
//  no-op placeholder field so the many `qbtcClaimPayload: nil` call sites
//  don't churn — under the post-qbtc#158 flow the proof service signs and
//  broadcasts `MsgClaimWithProof` directly, so iOS never constructs one
//  of these.
//

import Foundation

struct QBTCClaimPayload: Codable, Hashable {
    let proofHex: String
    let messageHashHex: String
    let addressHashHex: String
    let qbtcAddressHashHex: String
    let pubKeyHashSha256Hex: String
    let utxos: [ClaimableUtxo]
}
