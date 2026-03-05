//
//  TransactionHistoryViewModel.swift
//  VultisigApp
//

import Foundation
import SwiftUI

struct TransactionHistoryCoinAsset: Hashable {
    let ticker: String
    let logo: String
    let chainLogo: String?
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
            print("TransactionHistoryViewModel: Failed to load: \(error)")
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
            ) { [weak self] newStatus in
                self?.updateTransaction(txHash: tx.txHash, status: newStatus)
            }
        }
    }

    private func updateTransaction(txHash: String, status: TransactionHistoryStatus) {
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
            estimatedTime: old.estimatedTime
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

    var groupedTransactions: [(String, [TransactionHistoryData])] {
        let calendar = Calendar.current
        let now = Date()

        var groups: [String: [TransactionHistoryData]] = [:]
        var groupOrder: [String] = []

        for tx in filteredTransactions {
            let key: String
            if calendar.isDateInToday(tx.createdAt) {
                key = "today".localized
            } else if calendar.isDateInYesterday(tx.createdAt) {
                key = "yesterday".localized
            } else if calendar.isDate(tx.createdAt, equalTo: now, toGranularity: .weekOfYear) {
                let formatter = DateFormatter()
                formatter.dateFormat = "EEEE"
                key = formatter.string(from: tx.createdAt)
            } else {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .none
                key = formatter.string(from: tx.createdAt)
            }

            if groups[key] == nil {
                groups[key] = []
                groupOrder.append(key)
            }
            groups[key]?.append(tx)
        }

        return groupOrder.compactMap { key in
            guard let items = groups[key] else { return nil }
            return (key, items)
        }
    }

    // MARK: - Available Coins for Filter

    var availableCoins: [(ticker: String, logo: String, chainLogo: String?)] {
        var seen = Set<String>()
        var result: [(ticker: String, logo: String, chainLogo: String?)] = []

        for tx in transactions {
            if !seen.contains(tx.coinTicker) {
                seen.insert(tx.coinTicker)
                result.append((ticker: tx.coinTicker, logo: tx.coinLogo, chainLogo: tx.coinChainLogo))
            }
        }

        return result
    }

    var filteredAvailableCoins: [TransactionHistoryCoinAsset] {
        let coins = availableCoins.map {
            TransactionHistoryCoinAsset(ticker: $0.ticker, logo: $0.logo, chainLogo: $0.chainLogo)
        }

        guard !filterSearchText.isEmpty else { return coins }

        return coins.filter { $0.ticker.localizedCaseInsensitiveContains(filterSearchText) }
    }

    // MARK: - Chain Filter Display

    var chainFilterName: String? {
        chainFilter?.name
    }
}
