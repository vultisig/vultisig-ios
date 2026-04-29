//
//  QBTCClaimContext.swift
//  VultisigApp
//
//  Round-1 context for a SecureVault QBTC claim. Round-trips through
//  the QR'd `KeysignPayload` (proto-backed via `VSQbtcClaimContext`)
//  so the peer device can compute round-1's message hash independently
//  and later reconstruct round-2's SignDoc.
//
//  See [[projects/vultisig/qbtc-claim/v2-secure-vault-design]] for
//  the protocol and rationale.
//

import Foundation
import VultisigCommonData

struct QBTCClaimContext: Codable, Hashable {
    /// QBTC bech32 address of the claimer. Used both as round-1's
    /// `qbtcAddress` input to the message-hash construction and as
    /// round-2's `claimer` field on `MsgClaimWithProof`.
    let claimerAddress: String
    /// User-selected UTXOs being claimed. Round-1 doesn't use these
    /// for message-hash computation, but they're needed by the peer
    /// to reconstruct round-2's SignDoc once the round-2 prep arrives
    /// over the relay.
    let utxos: [ClaimableUtxo]
    /// Base relay session id. Per-round sessions use deterministic
    /// suffixes — `{baseSessionID}-0` (BTC ECDSA) and
    /// `{baseSessionID}-1` (MLDSA). Both initiator and peer derive
    /// these from the base.
    let baseSessionID: String

    init(claimerAddress: String, utxos: [ClaimableUtxo], baseSessionID: String) {
        self.claimerAddress = claimerAddress
        self.utxos = utxos
        self.baseSessionID = baseSessionID
    }

    init(proto: VSQbtcClaimContext) {
        self.claimerAddress = proto.claimerAddress
        self.utxos = proto.utxos.map { proto in
            ClaimableUtxo(txid: proto.txid, vout: proto.vout, amount: proto.amount)
        }
        self.baseSessionID = proto.baseSessionID
    }

    func mapToProtobuff() -> VSQbtcClaimContext {
        .with {
            $0.claimerAddress = claimerAddress
            $0.utxos = utxos.map { utxo in
                VSQbtcClaimUtxoRef.with {
                    $0.txid = utxo.txid
                    $0.vout = utxo.vout
                    $0.amount = utxo.amount
                }
            }
            $0.baseSessionID = baseSessionID
        }
    }
}
