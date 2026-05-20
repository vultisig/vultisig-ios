//
//  SwapKitTrackingStatusMapper.swift
//  VultisigApp
//
//  Pure mapping from SwapKit's 14-value `trackingStatus` enum to the smaller
//  iOS-side enum the tx-history UI renders. Kept as a free function so unit
//  tests can exercise every branch without instantiating the tracking service.
//
//  The full TrackingStatus → UI table (see the SwapKit tx-history plan §"State
//  mapping"):
//
//    not_started, starting, broadcasted, mempool, inbound  → pending
//    outbound, swapping                                    → swapping
//    completed                                             → completed
//    refunded, partially_refunded                          → refunded
//    dropped, reverted, replaced, retries_exceeded,
//      parsing_error                                       → failed
//    (anything unrecognised)                               → pending
//
//  The 7-value coarse `status` (`TxnStatus`) is mapped via
//  `SwapKitTrackingStatus` (defined alongside the API response). The fine-
//  grained `trackingStatus` always wins when both are present — it conveys
//  more useful information for the UI (e.g. "outbound" → swapping rather
//  than "pending").
//

import Foundation

/// Coarse UI state surfaced by the tx-history list cell, detail sheet, and
/// done-screen banner. Maps to the design-system colours and pill copy.
enum SwapKitUiStatus: String, Codable, Sendable, Hashable {
    case pending
    case swapping
    case completed
    case refunded
    case failed
    /// Sentinel for the "stuck in `unknown` past the give-up window" path —
    /// rendered identically to `failed` but kept distinct so we can surface
    /// "tracker unavailable, check explorer" copy and analytics.
    case unknownPendingExtended
}

extension SwapKitUiStatus {
    /// Terminal states never get polled again.
    var isTerminal: Bool {
        switch self {
        case .completed, .refunded, .failed, .unknownPendingExtended:
            return true
        case .pending, .swapping:
            return false
        }
    }
}

enum SwapKitTrackingStatusMapper {
    /// Map the wire-string `trackingStatus` value into the iOS UI state.
    /// Pure — no side effects. Unknown / unrecognised values fall through to
    /// `pending` so a future SwapKit-side enum value doesn't crash the UI;
    /// the "stuck in unknown" path is policed by the polling service via
    /// the elapsed-time check, not by this function.
    static func map(trackingStatus raw: String?) -> SwapKitUiStatus {
        guard let raw = raw?.lowercased(), !raw.isEmpty else {
            return .pending
        }
        switch raw {
        case "not_started", "starting", "broadcasted", "mempool", "inbound":
            return .pending
        case "outbound", "swapping":
            return .swapping
        case "completed":
            return .completed
        case "refunded", "partially_refunded":
            return .refunded
        case "dropped", "reverted", "replaced", "retries_exceeded", "parsing_error", "failed":
            return .failed
        case "unknown":
            return .pending
        default:
            return .pending
        }
    }

    /// Fallback path used when only the coarse `status` field is populated.
    /// Mirrors the `trackingStatus` table at a coarser granularity.
    static func map(coarseStatus status: SwapKitTrackingStatus) -> SwapKitUiStatus {
        switch status {
        case .notStarted, .pending:
            return .pending
        case .swapping:
            return .swapping
        case .completed:
            return .completed
        case .refunded:
            return .refunded
        case .failed:
            return .failed
        case .unknown:
            return .pending
        }
    }

    /// Combined mapping — prefers the fine-grained `trackingStatus` when
    /// present, falls back to the coarse `status` otherwise. Centralised so
    /// the tracking service and the UI agree on the precedence rule.
    static func map(_ response: SwapKitTrackingResponse) -> SwapKitUiStatus {
        if let raw = response.trackingStatus, !raw.isEmpty {
            return map(trackingStatus: raw)
        }
        return map(coarseStatus: response.status)
    }
}
