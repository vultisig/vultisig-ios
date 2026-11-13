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
    /// Why swapping this row makes no sense right now ("Allow + swap gas $2.12
    /// is more than it is worth"). Shown, never hidden: the row stays pickable.
    var unswappableReason: String?
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

    /// Rows under `threshold` in fiat fold into one "Small balances" row.
    static let smallBalanceThreshold: Decimal = 1

    static func split(_ rows: [SwapReworkPickerRow], threshold: Decimal = smallBalanceThreshold) -> (main: [SwapReworkPickerRow], small: [SwapReworkPickerRow]) {
        (rows.filter { $0.fiatValue >= threshold }, rows.filter { $0.fiatValue < threshold })
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
    /// "9:41" when a stage was first seen done, "now" for the active one.
    var stageTimes: [SwapTrackerStage.Kind: String] = [:]
    /// What a pending leg is waiting on: "~1 min · Ethereum confirmations".
    var legNotes: [SwapTrackerStage.Kind: String] = [:]
}

enum SwapTrackerLegNotes {
    /// Notes for the legs not done yet, from the quote's own leg times and
    /// what is known about the destination chain's blocks.
    static func make(
        stages: [SwapTrackerStage],
        times: SwapLegTimes?,
        sourceChain: String,
        providerName: String,
        destinationIsBitcoin: Bool
    ) -> [SwapTrackerStage.Kind: String] {
        var notes: [SwapTrackerStage.Kind: String] = [:]
        for stage in stages where stage.status != .done {
            switch stage.kind {
            case .sent:
                if let seconds = times?.inboundSeconds {
                    notes[.sent] = String(format: "swapReworkLegConfirmations".localized, SwapLegTimes.minutesText(seconds: seconds), sourceChain)
                }
            case .swapped:
                if let seconds = times?.swapLegSeconds {
                    notes[.swapped] = String(format: "swapReworkLegOutbound".localized, SwapLegTimes.minutesText(seconds: seconds), providerName)
                }
            case .received:
                if destinationIsBitcoin {
                    notes[.received] = "swapReworkLegBitcoinBlocks".localized
                }
            }
        }
        return notes
    }
}

struct SwapReworkSuccessState: Equatable {
    let receive: SwapReworkAsset
    let vaultName: String
    /// False while only the quote is known: the screen then says "expected"
    /// and never labels the quoted amount as delivered.
    let isDeliveredKnown: Bool
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
