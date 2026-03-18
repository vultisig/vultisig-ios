//
//  TransactionHistoryData.swift
//  VultisigApp
//

import Foundation

// MARK: - Type Enum

enum TransactionHistoryType: String, Codable, Sendable, Hashable {
    case send
    case swap
    case approve
}

// MARK: - Status Enum

enum TransactionHistoryStatus: String, Codable, Sendable, Hashable {
    case inProgress
    case successful
    case error
}

// MARK: - Sendable Value Type

struct TransactionHistoryData: Sendable, Hashable, Identifiable {
    let id: UUID
    let txHash: String
    let approveTxHash: String?
    let pubKeyECDSA: String
    let type: TransactionHistoryType
    let status: TransactionHistoryStatus
    let chainRawValue: String
    let coinTicker: String
    let coinLogo: String
    let coinChainLogo: String?
    let amountCrypto: String
    let amountFiat: String
    let fromAddress: String
    let toAddress: String
    let toCoinTicker: String?
    let toCoinLogo: String?
    let toCoinChainLogo: String?
    let toAmountCrypto: String?
    let toAmountFiat: String?
    let swapProvider: String?
    let feeCrypto: String
    let feeFiat: String
    let network: String
    let explorerLink: String
    let createdAt: Date
    let completedAt: Date?
    let estimatedTime: String?
    let errorMessage: String?
}

// MARK: - Conversions

extension TransactionHistoryData {

    @MainActor
    init(item: TransactionHistoryItem) {
        self.id = item.id
        self.txHash = item.txHash
        self.approveTxHash = item.approveTxHash
        self.pubKeyECDSA = item.pubKeyECDSA
        self.type = TransactionHistoryType(rawValue: item.typeRawValue) ?? .send
        self.status = TransactionHistoryStatus(rawValue: item.statusRawValue) ?? .inProgress
        self.chainRawValue = item.chainRawValue
        self.coinTicker = item.coinTicker
        self.coinLogo = item.coinLogo
        self.coinChainLogo = item.coinChainLogo
        self.amountCrypto = item.amountCrypto
        self.amountFiat = item.amountFiat
        self.fromAddress = item.fromAddress
        self.toAddress = item.toAddress
        self.toCoinTicker = item.toCoinTicker
        self.toCoinLogo = item.toCoinLogo
        self.toCoinChainLogo = item.toCoinChainLogo
        self.toAmountCrypto = item.toAmountCrypto
        self.toAmountFiat = item.toAmountFiat
        self.swapProvider = item.swapProvider
        self.feeCrypto = item.feeCrypto
        self.feeFiat = item.feeFiat
        self.network = item.network
        self.explorerLink = item.explorerLink
        self.createdAt = item.createdAt
        self.completedAt = item.completedAt
        self.estimatedTime = item.estimatedTime
        self.errorMessage = item.errorMessage
    }

    func toItem() -> TransactionHistoryItem {
        TransactionHistoryItem(
            id: id,
            txHash: txHash,
            approveTxHash: approveTxHash,
            pubKeyECDSA: pubKeyECDSA,
            typeRawValue: type.rawValue,
            statusRawValue: status.rawValue,
            chainRawValue: chainRawValue,
            coinTicker: coinTicker,
            coinLogo: coinLogo,
            coinChainLogo: coinChainLogo,
            amountCrypto: amountCrypto,
            amountFiat: amountFiat,
            fromAddress: fromAddress,
            toAddress: toAddress,
            toCoinTicker: toCoinTicker,
            toCoinLogo: toCoinLogo,
            toCoinChainLogo: toCoinChainLogo,
            toAmountCrypto: toAmountCrypto,
            toAmountFiat: toAmountFiat,
            swapProvider: swapProvider,
            feeCrypto: feeCrypto,
            feeFiat: feeFiat,
            network: network,
            explorerLink: explorerLink,
            createdAt: createdAt,
            completedAt: completedAt,
            estimatedTime: estimatedTime,
            errorMessage: errorMessage
        )
    }
}
