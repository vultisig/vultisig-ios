//
//  SwapReworkPickerModels.swift
//  VultisigApp
//
//  Rows of the reworked token picker, and the tracker / success values, as
//  plain data shared by the live screens and the debug demo fixtures.
//

import Foundation

struct SwapReworkPickerRow: Equatable, Identifiable {
    let asset: SwapReworkAsset
    let contract: String
    let balanceText: String
    let fiatText: String
    let fiatValue: Decimal
    let trust: SwapTokenTrust
    var id: String { asset.coinID }
}

enum SwapReworkPickerFilter {
    /// Rows for a chain chip (nil = all) and a query matched against ticker,
    /// chain name and contract. Highest fiat balance first; ties by ticker.
    static func rows(_ rows: [SwapReworkPickerRow], chainName: String?, query: String) -> [SwapReworkPickerRow] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return rows
            .filter { chainName == nil || $0.asset.chainName == chainName }
            .filter { row in
                guard !needle.isEmpty else { return true }
                return row.asset.ticker.lowercased().contains(needle)
                    || row.asset.chainName.lowercased().contains(needle)
                    || (!row.contract.isEmpty && row.contract.lowercased().hasPrefix(needle))
            }
            .sorted { lhs, rhs in
                if lhs.fiatValue != rhs.fiatValue { return lhs.fiatValue > rhs.fiatValue }
                return lhs.asset.ticker < rhs.asset.ticker
            }
    }

    /// Recents that are still in the list, in recency order.
    static func recents(_ ids: [String], in rows: [SwapReworkPickerRow]) -> [SwapReworkPickerRow] {
        ids.compactMap { id in rows.first { $0.id == id } }
    }

    /// Chain chips in the order of the largest holding on each chain.
    static func chains(_ rows: [SwapReworkPickerRow]) -> [String] {
        var totals: [String: Decimal] = [:]
        for row in rows { totals[row.asset.chainName, default: 0] += row.fiatValue }
        return totals.sorted { lhs, rhs in
            lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key < rhs.key
        }.map(\.key)
    }
}

struct SwapReworkTrackerState: Equatable {
    let pay: SwapReworkAsset
    let receive: SwapReworkAsset
    let receiveAmountText: String
    let providerName: String
    let stages: [SwapTrackerStage]
    let phase: SwapTrackerPhase
    /// "Usually 6-9 min more"
    let remainingText: String?
    let sentDetail: String
    let swappedDetail: String
    let receivedDetail: String
    let isCrossChain: Bool
}

struct SwapReworkSuccessState: Equatable {
    let receive: SwapReworkAsset
    let vaultName: String
    let deliveredText: String
    let deliveredFiatText: String
    let quotedText: String
    let outcome: SwapOutcome?
    /// "+190 sats · +0.01%"
    let differenceText: String?
    let tookText: String?
    let feesText: String
    let tierName: String?
    let tierSavedText: String?
}
