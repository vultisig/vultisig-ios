//
//  QBTCClaimResultMessage.swift
//  VultisigApp
//
//  Out-of-band payload pushed from the initiator to the co-signer over
//  the relay's setup-message channel after the proof service returns.
//  Lets the peer device transition to the same done screen as the
//  initiator with the on-chain tx hash + status polling. Carried via
//  `KeysignSessionService.pushSetupMessage` / `pollSetupMessage`.
//

import Foundation

struct QBTCClaimResultMessage: Codable {
    /// Fixed relay message ID for the initiator → peer tx-hash push.
    static let messageID = "qbtc-claim-result"

    let txHash: String
    /// Total sats the initiator selected for the claim. The peer needs
    /// this to render the amount on its done screen — there's no
    /// on-chain way for the peer to know it.
    let totalSats: UInt64
}
