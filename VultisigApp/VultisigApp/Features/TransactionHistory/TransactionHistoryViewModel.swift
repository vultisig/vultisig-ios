//
//  TransactionHistoryViewModel.swift
//  VultisigApp
//

import Foundation
import OSLog
import SwiftUI

struct TransactionHistoryCoinAsset: Hashable {
    let ticker: String
    let logo: String
    let chainLogo: String?
    let network: String
}

@MainActor
class TransactionHistoryViewModel: ObservableObject {
    @Published var transactions: [TransactionHistoryData] = []
    @Published var selectedTab: TransactionHistoryTab = .overview
    @Published var selectedAssetFilters: Set<String> = []
    @Published var showAssetFilter = false
    @Published var filterSearchText = ""
    @Published var selectedDetail: TransactionHistoryData?

    let pubKeyECDSA: String
    let vaultName: String
    let chainFilter: Chain?

    private let storage = TransactionHistoryStorage.shared
    private let poller = TransactionStatusPoller.shared
    private let logger = Logger(subsystem: "com.vultisig.app", category: "tx-history-viewmodel")

    init(pubKeyECDSA: String, vaultName: String, chainFilter: Chain?) {
        self.pubKeyECDSA = pubKeyECDSA
        self.vaultName = vaultName
        self.chainFilter = chainFilter
    }

    // MARK: - Loading

    func load() {
        do {
            if let chain = chainFilter {
                transactions = try storage.fetchByChain(pubKeyECDSA: pubKeyECDSA, chainRawValue: chain.rawValue)
            } else {
                transactions = try storage.fetchAll(pubKeyECDSA: pubKeyECDSA)
            }
            pollInProgressTransactions()
        } catch {
            logger.error("Failed to load: \(error)")
        }
    }

    func refresh() async {
        load()
        // Allow pull-to-refresh animation to complete
        try? await Task.sleep(for: .milliseconds(300))
    }

    func stopPolling() {
        for tx in transactions where tx.status == .inProgress {
            poller.stopPolling(txHash: tx.txHash)
        }
    }

    // MARK: - Status Polling

    private func pollInProgressTransactions() {
        for tx in transactions where tx.status == .inProgress {
            guard let chain = Chain(rawValue: tx.chainRawValue) else { continue }

            poller.poll(
                txHash: tx.txHash,
                chain: chain,
                pubKeyECDSA: pubKeyECDSA
            ) { [weak self] newStatus, errorMessage in
                self?.updateTransaction(txHash: tx.txHash, status: newStatus, errorMessage: errorMessage)
            }
        }
    }

    private func updateTransaction(txHash: String, status: TransactionHistoryStatus, errorMessage: String? = nil) {
        guard let index = transactions.firstIndex(where: { $0.txHash == txHash }) else { return }

        let old = transactions[index]
        transactions[index] = TransactionHistoryData(
            id: old.id,
            txHash: old.txHash,
            approveTxHash: old.approveTxHash,
            pubKeyECDSA: old.pubKeyECDSA,
            type: old.type,
            status: status,
            chainRawValue: old.chainRawValue,
            coinTicker: old.coinTicker,
            coinLogo: old.coinLogo,
            coinChainLogo: old.coinChainLogo,
            amountCrypto: old.amountCrypto,
            amountFiat: old.amountFiat,
            fromAddress: old.fromAddress,
            toAddress: old.toAddress,
            toCoinTicker: old.toCoinTicker,
            toCoinLogo: old.toCoinLogo,
            toCoinChainLogo: old.toCoinChainLogo,
            toAmountCrypto: old.toAmountCrypto,
            toAmountFiat: old.toAmountFiat,
            swapProvider: old.swapProvider,
            feeCrypto: old.feeCrypto,
            feeFiat: old.feeFiat,
            network: old.network,
            explorerLink: old.explorerLink,
            createdAt: old.createdAt,
            completedAt: Date(),
            estimatedTime: old.estimatedTime,
            errorMessage: errorMessage ?? old.errorMessage
        )
    }

    // MARK: - Filtered Transactions

    var filteredTransactions: [TransactionHistoryData] {
        var result = transactions

        // Tab filter
        switch selectedTab {
        case .overview:
            break
        case .swaps:
            result = result.filter { $0.type == .swap }
        case .send:
            result = result.filter { $0.type == .send || $0.type == .approve }
        }

        // Asset filter
        if !selectedAssetFilters.isEmpty {
            result = result.filter { selectedAssetFilters.contains($0.coinTicker) }
        }

        return result
    }

    // MARK: - Grouped by Date

    var groupedTransactions: [(title: String, subtitle: String?, transactions: [TransactionHistoryData])] {
        let calendar = Calendar.current
        let now = Date()

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d, yyyy"

        var groups: [String: [TransactionHistoryData]] = [:]
        var groupMeta: [String: (title: String, subtitle: String?)] = [:]
        var groupOrder: [String] = []

        for tx in filteredTransactions {
            let key: String
            let title: String
            let subtitle: String?

            if calendar.isDateInToday(tx.createdAt) {
                key = "today"
                title = "today".localized
                subtitle = dateFormatter.string(from: tx.createdAt)
            } else if calendar.isDateInYesterday(tx.createdAt) {
                key = "yesterday"
                title = "yesterday".localized
                subtitle = dateFormatter.string(from: tx.createdAt)
            } else if calendar.isDate(tx.createdAt, equalTo: now, toGranularity: .weekOfYear) {
                let dayFormatter = DateFormatter()
                dayFormatter.dateFormat = "EEEE"
                key = dayFormatter.string(from: tx.createdAt)
                title = key
                subtitle = dateFormatter.string(from: tx.createdAt)
            } else {
                let mediumFormatter = DateFormatter()
                mediumFormatter.dateStyle = .medium
                mediumFormatter.timeStyle = .none
                key = mediumFormatter.string(from: tx.createdAt)
                title = key
                subtitle = nil
            }

            if groups[key] == nil {
                groups[key] = []
                groupMeta[key] = (title, subtitle)
                groupOrder.append(key)
            }
            groups[key]?.append(tx)
        }

        return groupOrder.compactMap { key in
            guard let items = groups[key], let meta = groupMeta[key] else { return nil }
            return (meta.title, meta.subtitle, items)
        }
    }

    // MARK: - Selected Filter Assets

    var selectedFilterAssets: [TransactionHistoryCoinAsset] {
        availableCoins.filter { selectedAssetFilters.contains($0.ticker) }
    }

    func clearAssetFilters() {
        selectedAssetFilters.removeAll()
    }

    func removeAssetFilter(_ ticker: String) {
        selectedAssetFilters.remove(ticker)
    }

    // MARK: - Available Coins for Filter

    var availableCoins: [TransactionHistoryCoinAsset] {
        var seen = Set<String>()
        var result: [TransactionHistoryCoinAsset] = []

        for tx in transactions {
            if !seen.contains(tx.coinTicker) {
                seen.insert(tx.coinTicker)
                result.append(TransactionHistoryCoinAsset(
                    ticker: tx.coinTicker,
                    logo: tx.coinLogo,
                    chainLogo: tx.coinChainLogo,
                    network: tx.network
                ))
            }
        }

        return result
    }

    var filteredAvailableCoins: [TransactionHistoryCoinAsset] {
        let coins = availableCoins

        guard !filterSearchText.isEmpty else { return coins }

        return coins.filter { $0.ticker.localizedCaseInsensitiveContains(filterSearchText) }
    }
}
