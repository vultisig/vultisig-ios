//
//  THORChainLimitTrackingStatusMapper.swift
//  VultisigApp
//
//  Maps a limit order's persisted status onto the tx-history row's UI state.
//  The limit-order counterpart to `SwapKitTrackingStatusMapper`, selected by
//  the `providerKind` dispatch on `TransactionHistoryData`.
//

import Foundation

enum THORChainLimitTrackingStatusMapper {
    /// Map the persisted tracking status onto the row's UI state.
    ///
    /// The wire vocabulary here is deliberately `LimitOrderStatus.rawValue`, not
    /// a parallel set of strings: `LimitOrder` is the authoritative record of an
    /// order, and the row merely mirrors it. Two vocabularies would be two
    /// things to keep in sync, and the row would eventually contradict the
    /// order it describes.
    ///
    /// Pure — no side effects. Anything unrecognised (including a status not yet
    /// recorded) maps to `.resting`, which is NON-terminal, so the tracker keeps
    /// polling and a later poll can correct it. The alternative — guessing a
    /// terminal state from a string we don't recognise — would end the order's
    /// life on a misunderstanding, and nothing revisits a terminal order.
    static func map(trackingStatus raw: String?) -> SwapTrackingUiStatus {
        guard let raw, let status = LimitOrderStatus(rawValue: raw) else {
            return .resting
        }
        return map(status)
    }

    static func map(_ status: LimitOrderStatus) -> SwapTrackingUiStatus {
        switch status {
        case .pending:
            // "Pending" on a limit order means resting in the queue, unfilled.
            return .resting
        case .filled:
            return .completed
        case .expired:
            return .expired
        case .cancelled:
            return .cancelled
        }
    }
}
