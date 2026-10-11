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
    var pubKeyECDSA: String?

    /// XRP only: the last ledger the signed transaction can be included in.
    /// Once the validated ledger passes it, a never-found transaction has
    /// expired. Optional so rows written before it existed migrate unchanged.
    var lastLedgerSequence: Int?

    init(
        txHash: String,
        chain: Chain,
        status: String = "broadcasted",
        estimatedTime: String,
        coinTicker: String? = nil,
        amount: String? = nil,
        toAddress: String? = nil,
        pubKeyECDSA: String? = nil,
        lastLedgerSequence: Int? = nil
    ) {
        self.txHash = txHash
        self.chain = chain
        self.status = status
        self.createdAt = Date()
        self.estimatedTime = estimatedTime
        self.coinTicker = coinTicker
        self.amount = amount
        self.toAddress = toAddress
        self.pubKeyECDSA = pubKeyECDSA
        self.lastLedgerSequence = lastLedgerSequence
    }
}

extension StoredPendingTransaction {
    /// The account that sent this row: rows keep no sender, so it is `vault`'s
    /// own account on the row's chain, which NEAR's status lookup needs.
    func senderAccountId(in vault: Vault) -> String? {
        vault.nativeCoin(for: chain)?.address
    }
}
