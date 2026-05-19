//
//  ClaimableUtxo.swift
//  VultisigApp
//

import Foundation

struct ClaimableUtxo: Codable, Hashable {
    let txid: String
    let vout: UInt32
    /// BTC amount in satoshis.
    let amount: UInt64
    /// Bitcoin block height where this UTXO was first confirmed. Optional
    /// because the Blockchair API can omit `block_id` on freshly-mined or
    /// mempool entries — UI treats `nil` as "Pending".
    let blockHeight: UInt32?
}
