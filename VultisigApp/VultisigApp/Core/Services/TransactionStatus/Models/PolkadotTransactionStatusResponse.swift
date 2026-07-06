//
//  PolkadotTransactionStatusResponse.swift
//  VultisigApp
//
//  Created by Claude on 27/01/2025.
//

import Foundation

/// JSON-RPC response for `chain_getBlock`.
///
/// `result.block` carries the signed block: `extrinsics` is the list of
/// hex-encoded extrinsics in the block (each blake2b-256 hashed to match a tx
/// hash), and `header.parentHash` links to the previous block so the status
/// provider can walk the chain backwards. `error` is populated when the node
/// rejects the call.
struct PolkadotTransactionStatusResponse: Codable {
    let result: PolkadotBlockResult?
    let error: PolkadotRPCError?

    struct PolkadotBlockResult: Codable {
        let block: PolkadotBlock
    }

    struct PolkadotBlock: Codable {
        let header: PolkadotBlockHeader
        let extrinsics: [String]
    }

    struct PolkadotBlockHeader: Codable {
        let parentHash: String
    }

    struct PolkadotRPCError: Codable {
        let code: Int
        let message: String
    }
}
