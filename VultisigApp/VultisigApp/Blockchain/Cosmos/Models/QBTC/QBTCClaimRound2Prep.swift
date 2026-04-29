//
//  QBTCClaimRound2Prep.swift
//  VultisigApp
//
//  Inter-round message the initiator pushes to the peer device after
//  the proof service responds and the QBTC chain account info is
//  fetched. Carries everything the peer needs to reconstruct round 2's
//  SignDoc independently and verify what they're being asked to sign.
//
//  Transported as JSON over the existing relay-message channel
//  (`POST {relay}/message/{baseSessionID}-1/...`). NOT in proto today —
//  the type contract lives in iOS / Android / Windows code, which is
//  fine because we control all consumers (per [[v2-secure-vault-design]]).
//

import Foundation

struct QBTCClaimRound2Prep: Codable, Hashable {
    /// PLONK proof returned by the proof service (`/prove`).
    let proofHex: String
    /// 64-hex; SDK-side `message_hash` from `/prove`. Should match
    /// the messageHashHex the peer computed locally during round 1 —
    /// peer MUST verify before signing.
    let messageHashHex: String
    /// 40-hex; `address_hash` from `/prove`.
    let addressHashHex: String
    /// 64-hex; `qbtc_address_hash` from `/prove`.
    let qbtcAddressHashHex: String
    /// QBTC chain account number — fetched from `/cosmos/auth/.../accounts/{addr}`
    /// (404 ⇒ 0 fresh-account).
    let accountNumber: UInt64
    /// QBTC chain sequence number — same source as `accountNumber`.
    let sequence: UInt64
}
