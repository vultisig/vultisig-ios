//
//  PolkadotTransactionStatusResponse.swift
//  VultisigApp
//
//  Created by Claude on 27/01/2025.
//

import Foundation

/// JSON-RPC response for `author_pendingExtrinsics`.
///
/// `result` is the list of hex-encoded extrinsics currently in the node's
/// transaction pool. `error` is populated when the node rejects the call.
struct PolkadotTransactionStatusResponse: Codable {
    let result: [String]?
    let error: PolkadotRPCError?

    struct PolkadotRPCError: Codable {
        let code: Int
        let message: String
    }
}
