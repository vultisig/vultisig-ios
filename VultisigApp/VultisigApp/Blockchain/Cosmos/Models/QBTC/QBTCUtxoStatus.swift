//
//  QBTCUtxoStatus.swift
//  VultisigApp
//
//  Per-UTXO claim eligibility as reported by the QBTC chain. The keeper
//  zeroes `entitled_amount` after a successful mint
//  (`x/qbtc/keeper/handle_msg_claim_with_proof.go`), so it doubles as the
//  "already claimed" signal. A 404 from the REST gateway means bifrost
//  has not indexed the UTXO yet — eligible later, not now.
//

import Foundation

enum QBTCUtxoStatus: Equatable {
    /// Chain knows the UTXO and `entitled_amount > 0`. Mint will succeed.
    case claimable(entitledAmount: UInt64)
    /// Chain knows the UTXO but `entitled_amount == 0`. Already claimed.
    case claimed
    /// Chain returned 404 — bifrost has not indexed this UTXO yet.
    case notIndexed
}

/// Wire-shape for `GET /qbtc/v1/utxo/{txid}/{vout}`. Mirrors the proto
/// `QueryUTXOResponse` in `qbtc/proto/qbtc/qbtc/v1/query_utxo.proto`,
/// minimal to what the filter cares about. Cosmos SDK protojson encodes
/// uint64 as a JSON string.
struct QBTCUtxoQueryResponse: Codable {
    let utxo: Utxo

    struct Utxo: Codable {
        let txid: String
        let entitledAmount: String

        enum CodingKeys: String, CodingKey {
            case txid
            case entitledAmount = "entitled_amount"
        }
    }
}
