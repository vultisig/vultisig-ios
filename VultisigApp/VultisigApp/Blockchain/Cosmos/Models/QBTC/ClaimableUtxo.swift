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
}
