//
//  TransactionStatusProvider.swift
//  VultisigApp
//
//  Created by Claude on 23/01/2025.
//

import Foundation

protocol TransactionStatusProvider {
    /// Check if transaction is confirmed on chain
    func checkStatus(txHash: String, chain: Chain) async throws -> TransactionStatusResult
}
