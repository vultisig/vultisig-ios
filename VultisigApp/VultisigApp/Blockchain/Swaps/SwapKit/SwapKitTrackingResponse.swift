//
//  SwapKitTrackingResponse.swift
//  VultisigApp
//
//  Decodable model for `POST /track`. Phase 1 ships with an explorer-link
//  fallback only — the polling integration into iOS tx history is covered by
//  the follow-up `track-in-tx-history-plan`. This stub exists so the
//  `SwapKitAPI.track` request has a return type and the future polling work
//  doesn't have to revisit the API enum.
//

import Foundation

struct SwapKitTrackingResponse: Decodable, Hashable {
    let chainId: String?
    let hash: String?
    let block: Int?
    let type: String?
    let status: SwapKitTrackingStatus
    let trackingStatus: String?
    let fromAsset: String?
    let fromAmount: String?
    let fromAddress: String?
    let toAsset: String?
    let toAmount: String?
    let toAddress: String?
    let finalisedAt: Double?
}

/// Subset of the documented 7-value `TxnStatus` enum exposed to iOS callers.
/// `unknown` covers values the API may add in the future without forcing a
/// decoder bump.
enum SwapKitTrackingStatus: String, Decodable {
    case notStarted = "not_started"
    case pending
    case swapping
    case completed
    case refunded
    case failed
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SwapKitTrackingStatus(rawValue: raw) ?? .unknown
    }
}
