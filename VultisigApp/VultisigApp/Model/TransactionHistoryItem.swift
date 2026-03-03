//
//  TransactionHistoryItem.swift
//  VultisigApp
//

import Foundation
import SwiftData

@Model
final class TransactionHistoryItem {
    var id: UUID
    var txHash: String
    var approveTxHash: String?
    var pubKeyECDSA: String

    // Type & Status stored as raw strings for SwiftData compatibility
    var typeRawValue: String
    var statusRawValue: String

    // Chain
    var chainRawValue: String

    // Snapshotted coin info (survives coin removal)
    var coinTicker: String
    var coinLogo: String
    var coinChainLogo: String?

    // Amounts
    var amountCrypto: String
    var amountFiat: String

    // Addresses
    var fromAddress: String
    var toAddress: String

    // Swap-specific
    var toCoinTicker: String?
    var toCoinLogo: String?
    var toCoinChainLogo: String?
    var toAmountCrypto: String?
    var toAmountFiat: String?
    var swapProvider: String?

    // Fee
    var feeCrypto: String
    var feeFiat: String

    // Network & Explorer
    var network: String
    var explorerLink: String

    // Timestamps
    var createdAt: Date
    var completedAt: Date?

    // Estimated time for in-progress display
    var estimatedTime: String?

    init(
        id: UUID = UUID(),
        txHash: String,
        approveTxHash: String? = nil,
        pubKeyECDSA: String,
        typeRawValue: String,
        statusRawValue: String,
        chainRawValue: String,
        coinTicker: String,
        coinLogo: String,
        coinChainLogo: String? = nil,
        amountCrypto: String,
        amountFiat: String,
        fromAddress: String,
        toAddress: String,
        toCoinTicker: String? = nil,
        toCoinLogo: String? = nil,
        toCoinChainLogo: String? = nil,
        toAmountCrypto: String? = nil,
        toAmountFiat: String? = nil,
        swapProvider: String? = nil,
        feeCrypto: String,
        feeFiat: String,
        network: String,
        explorerLink: String,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        estimatedTime: String? = nil
    ) {
        self.id = id
        self.txHash = txHash
        self.approveTxHash = approveTxHash
        self.pubKeyECDSA = pubKeyECDSA
        self.typeRawValue = typeRawValue
        self.statusRawValue = statusRawValue
        self.chainRawValue = chainRawValue
        self.coinTicker = coinTicker
        self.coinLogo = coinLogo
        self.coinChainLogo = coinChainLogo
        self.amountCrypto = amountCrypto
        self.amountFiat = amountFiat
        self.fromAddress = fromAddress
        self.toAddress = toAddress
        self.toCoinTicker = toCoinTicker
        self.toCoinLogo = toCoinLogo
        self.toCoinChainLogo = toCoinChainLogo
        self.toAmountCrypto = toAmountCrypto
        self.toAmountFiat = toAmountFiat
        self.swapProvider = swapProvider
        self.feeCrypto = feeCrypto
        self.feeFiat = feeFiat
        self.network = network
        self.explorerLink = explorerLink
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.estimatedTime = estimatedTime
    }
}
