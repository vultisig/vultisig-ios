//
//  QBTCClaimContext.swift
//  VultisigApp
//
//  Sanity-check context for a SecureVault QBTC claim. Round-trips
//  through the QR'd `KeysignPayload` (proto-backed via
//  `VSQbtcClaimContext`). The peer device derives the BTC ECDSA
//  message hash from `claimerAddress` (plus its own vault BTC
//  address + pubkey + chain id) and signs THAT, so a compromised
//  initiator cannot divert the signature to an arbitrary BTC
//  spending tx.
//
//  Under the post-qbtc#158 flow the proof service signs and broadcasts
//  `MsgClaimWithProof` itself, so this context no longer carries the
//  UTXO list or the relay base-session id — those were both for the
//  deleted round-2 SignDoc reconstruction.
//

import Foundation
import VultisigCommonData

struct QBTCClaimContext: Codable, Hashable {
    /// QBTC bech32 address of the claimer. The only piece of state the
    /// peer device can't derive from its own vault — without it the
    /// peer can't compute the round-1 message hash to sanity-check
    /// against what the initiator asks it to sign.
    let claimerAddress: String

    init(claimerAddress: String) {
        self.claimerAddress = claimerAddress
    }

    init(proto: VSQbtcClaimContext) {
        self.claimerAddress = proto.claimerAddress
    }

    func mapToProtobuff() -> VSQbtcClaimContext {
        .with {
            $0.claimerAddress = claimerAddress
        }
    }
}
