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
}

protocol TransactionStatusProvider {
    /// Check if transaction is confirmed on chain
    func checkStatus(query: TransactionStatusQuery) async throws -> TransactionStatusResult
}
