//
//  TransactionStatusProvider.swift
//  VultisigApp
//
//  Created by Claude on 23/01/2025.
//

import Foundation

/// Query parameters for checking transaction status
struct TransactionStatusQuery {
    let txHash: String
    let chain: Chain
    /// Sender account id, where the chain's lookup needs it (NEAR looks the
    /// transaction up by `(tx_hash, sender_account_id)` because the lookup is
    /// sharded by sender). `nil` — the sender is unknown on this path — makes
    /// such a chain fail closed rather than guess.
    var senderAccountId: String?
}

protocol TransactionStatusProvider {
    /// Check if transaction is confirmed on chain
    func checkStatus(query: TransactionStatusQuery) async throws -> TransactionStatusResult
}
