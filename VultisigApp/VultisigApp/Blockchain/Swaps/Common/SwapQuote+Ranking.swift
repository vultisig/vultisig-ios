//
//  SwapQuote+Ranking.swift
//  VultisigApp
//

import Foundation
import BigInt

extension SwapQuote {

    /// Expected output amount in `toCoin` units, net of provider/inbound/outbound fees.
    /// Used to rank quotes from different providers — every provider in a candidate set swaps
    /// to the same `toCoin`, so this value is directly comparable.
    ///
    /// - THORChain/Maya: `expectedAmountOut` is already net of inbound + swap + outbound fees.
    /// - 1inch/KyberSwap: `dstAmount` is net of swap fees.
    /// - LiFi: `dstAmount` is already net of the integrator fee, which LI.FI takes from the
    ///   source token (`fromToken`) and reflects in `estimate.toAmount` (`included: true`).
    ///
    /// Source-chain gas is intentionally excluded from this destination-side metric: folding it
    /// in would require a cross-asset price (source-native wei → destination token) the ranker
    /// doesn't have, and it only applies to same-chain EVM aggregators — an asymmetric term that
    /// would disadvantage THORChain/Maya (no router gas at quote time). Source gas is instead
    /// applied as an in-band lower-gas tie-break in `selectBestQuote` via `sourceGasWei`, where
    /// the two compared EVM quotes share the same native-wei unit and no price lookup is needed.
    func expectedNetToAmount(toCoin: Coin) -> Decimal? {
        switch self {
        case .thorchain(let quote),
             .thorchainChainnet(let quote),
             .thorchainStagenet(let quote),
             .mayachain(let quote):
            guard let raw = Decimal(string: quote.expectedAmountOut), raw > 0 else { return nil }
            return raw / toCoin.thorswapMultiplier

        case .oneinch(let quote, _),
             .kyberswap(let quote, _),
             .lifi(let quote, _, _):
            guard let raw = BigInt(quote.dstAmount), raw > 0 else { return nil }
            return toCoin.decimal(for: raw)

        case .jupiter(let quote, _, _, _):
            // Jupiter `outAmount` is already net of the affiliate platform fee
            // (Jupiter deducts the fee from the AMM output and reports it
            // separately in `platformFee`), so it's the amount the user
            // receives — same convention as LiFi above. Do NOT subtract again.
            guard let raw = BigInt(quote.dstAmount), raw > 0 else { return nil }
            return toCoin.decimal(for: raw)

        case .swapkit(let response, _, _):
            // SwapKit's `expectedBuyAmount` is already a decimal string in
            // human units (not raw base units) — same wire choice the
            // aggregator made in its docs. Convert directly without applying
            // `toCoin.decimal`.
            guard let amount = Decimal(string: response.expectedBuyAmount), amount > 0 else { return nil }
            return amount
        }
    }
}
