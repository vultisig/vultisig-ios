//
//  LimitSwapQuoteServiceProtocol.swift
//  VultisigApp
//

import BigInt
import Foundation

/// Reference-data lookups the limit-swap interactor needs from THORChain.
///
/// Folded into a single protocol because both calls are facets of "talking
/// to THORChain for reference data" — the consumer is the limit-swap
/// interactor, not a generic quote consumer.
protocol LimitSwapQuoteServiceProtocol {

    /// Fetches the current market price for a pair, expressed as
    /// `target-asset natural units per source-asset natural unit`.
    ///
    /// Example: for BTC→ETH at the current rate, returns ~16.5 (16.5 ETH per
    /// 1 BTC), regardless of the source amount used to query.
    func fetchCurrentMarketPrice(
        sourceAsset: String,
        sourceAmount: BigInt,
        sourceDecimals: Int,
        targetAsset: String,
        targetDecimals: Int,
        destinationAddress: String
    ) async throws -> Decimal

    /// Fetches the THORChain inbound vault address for a given source chain
    /// (e.g. `BTC`, `ETH`, `LTC`). Returns `nil` if no inbound address is
    /// currently published (chain halted, paused, etc.).
    func fetchInboundAddress(forChainSymbol chainSymbol: String) async throws -> String?
}
