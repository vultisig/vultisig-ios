//
//  DestinationTokenBucket.swift
//  VultisigApp
//
//  Generic per-chain bucket returned by every `DestinationTokenProvider`.
//  Replaces the previous SwapKit-specific `SwapKitTokensBucket`.
//
//  `uniqueIds` is precomputed once at bucket build time so the picker's
//  merge step doesn't rebuild a `Set` per call. The picker dedups across
//  buckets by `CoinMeta.uniqueId` — see
//  `SwapCoinSelectionLogic.mergeExternal`.
//

import Foundation

struct DestinationTokenBucket: Sendable {
    let chain: Chain
    let tokens: [CoinMeta]
    let uniqueIds: Set<String>

    static func empty(chain: Chain) -> DestinationTokenBucket {
        DestinationTokenBucket(chain: chain, tokens: [], uniqueIds: [])
    }
}
