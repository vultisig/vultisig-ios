//
//  ThorchainService+LimitSwapQuote.swift
//  VultisigApp
//

import BigInt
import Foundation

extension ThorchainService: LimitSwapQuoteServiceProtocol {

    func fetchCurrentMarketPrice(
        sourceAsset: String,
        sourceAmount: BigInt,
        sourceDecimals: Int,
        targetAsset: String,
        targetDecimals: Int,
        destinationAddress: String
    ) async throws -> Decimal {
        let quote = try await fetchSwapQuotes(
            address: destinationAddress,
            fromAsset: sourceAsset,
            toAsset: targetAsset,
            amount: sourceAmount.description,
            interval: 1,
            streamingQuantity: 0,
            // No minimum-output limit on the reference quote — this fetch only
            // derives the market price for the form, it never broadcasts.
            toleranceBps: 0,
            referredCode: "",
            vultTierDiscount: 0
        )

        return try Self.marketPrice(
            expectedAmountOut: quote.expectedAmountOut,
            sourceAmount: sourceAmount,
            sourceDecimals: sourceDecimals
        )
    }

    /// Derive the market price (target natural units per source natural unit)
    /// from a quote's `expected_amount_out`. THORChain reports that in 1e8
    /// fixed-point regardless of the target chain's natural decimals. Pure +
    /// static so the 1e8 math and its three throw paths are unit-testable
    /// without a network round-trip.
    static func marketPrice(
        expectedAmountOut: String,
        sourceAmount: BigInt,
        sourceDecimals: Int
    ) throws -> Decimal {
        guard let expectedRaw = Decimal(string: expectedAmountOut) else {
            throw LimitSwapQuoteError.invalidExpectedAmount(expectedAmountOut)
        }
        let expectedTargetNatural = expectedRaw / pow(10, 8)

        guard let sourceRaw = Decimal(string: sourceAmount.description) else {
            throw LimitSwapQuoteError.invalidSourceAmount(sourceAmount.description)
        }
        let sourceNatural = sourceRaw / pow(10, sourceDecimals)
        guard sourceNatural != 0 else {
            throw LimitSwapQuoteError.zeroSourceAmount
        }

        return expectedTargetNatural / sourceNatural
    }

    func fetchInboundAddresses() async -> [InboundAddress] {
        await fetchThorchainInboundAddress()
    }

    /// The mimir key gating THORChain's Advanced Swap Queue — the on-chain
    /// feature that makes `=<` a real resting limit order.
    static let advancedSwapQueueMimirKey = "EnableAdvSwapQueue"

    /// Whether THORChain currently accepts resting limit orders (`=<`).
    ///
    /// The Advanced Swap Queue is gated by the `EnableAdvSwapQueue` mimir and
    /// has been toggled off/on across releases. **Fails CLOSED** — any fetch or
    /// parse failure returns `false` (limit orders blocked). A `=<` order placed
    /// while the queue is disabled can be treated as a market swap or rejected
    /// on-chain, executing at the wrong price: a fund-safety hazard. So the only
    /// value that unblocks placement is a live, confirmed `1`.
    func isAdvancedSwapQueueEnabled() async -> Bool {
        do {
            let response = try await httpClient.request(mainnet(.mimir(key: Self.advancedSwapQueueMimirKey)))
            return Self.parseMimirEnabled(response.data)
        } catch {
            logger.warning("EnableAdvSwapQueue mimir fetch failed; failing closed (limit orders disabled): \(error.localizedDescription)")
            return false
        }
    }

    /// Interpret a `/thorchain/mimir/key/<KEY>` response body. THORChain returns
    /// the value as a **bare integer** (verified: the endpoint responds `1`, not
    /// `"1"`). Only an exact `1` — after trimming surrounding whitespace/newlines
    /// — means ENABLED. Everything else fails CLOSED: `0`, `2` (market-only),
    /// `-1` (unset), a quoted `"1"`, `Int`-lenient variants (`+1`, `01`), decimals
    /// (`1.0`), empty, or unparseable. Deliberately NOT `Int`-parsed: on a HIGH-
    /// tier availability gate an over-broad accept set is worse than a rare
    /// false-block. Pure + static so it is unit-testable without a round-trip.
    static func parseMimirEnabled(_ data: Data) -> Bool {
        guard let raw = String(data: data, encoding: .utf8) else { return false }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }
}
