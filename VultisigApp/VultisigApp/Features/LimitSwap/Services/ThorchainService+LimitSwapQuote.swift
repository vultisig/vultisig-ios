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

        guard let expectedRaw = Decimal(string: quote.expectedAmountOut) else {
            throw LimitSwapQuoteError.invalidExpectedAmount(quote.expectedAmountOut)
        }
        // THORChain returns expected_amount_out in 1e8 fixed-point regardless
        // of the target chain's natural decimals.
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
    /// the value as a bare integer; only `1` means ENABLED. Anything else — `0`,
    /// `2` (market-only), `-1` (unset), quotes, surrounding whitespace, empty or
    /// unparseable bodies — fails CLOSED. Pure + static so it is unit-testable
    /// without a network round-trip.
    static func parseMimirEnabled(_ data: Data) -> Bool {
        guard let raw = String(data: data, encoding: .utf8) else { return false }
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: " \n\r\t\"'"))
        return Int(trimmed) == 1
    }
}
