//
//  PendingTransaction.swift
//  VultisigApp
//
//  Created by Claude on 23/01/2025.
//

import Foundation
import SwiftData

@Model
final class StoredPendingTransaction {
    @Attribute(.unique) var txHash: String
    var chain: Chain
    var status: String  // "broadcasted", "pending", "confirmed", "failed", "timeout"
    var createdAt: Date
    var lastCheckedAt: Date?
    var confirmedAt: Date?
    var failureReason: String?
    var estimatedTime: String

    // Metadata for display
    var coinTicker: String?
    var amount: String?
    var toAddress: String?

    init(
        txHash: String,
        chain: Chain,
        status: String = "broadcasted",
        estimatedTime: String,
        coinTicker: String? = nil,
        amount: String? = nil,
        toAddress: String? = nil
    ) {
        self.txHash = txHash
        self.chain = chain
        self.status = status
        self.createdAt = Date()
        self.estimatedTime = estimatedTime
        self.coinTicker = coinTicker
        self.amount = amount
        self.toAddress = toAddress
    }
}
