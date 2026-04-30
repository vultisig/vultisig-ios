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
    /// - LiFi: `dstAmount` minus integrator fee (charged on the output side).
    ///
    /// Source-chain gas is intentionally excluded: aggregators on a given chain consume similar
    /// gas (~200k units), so the destination output dominates the comparison. THORChain Router
    /// gas on EVM is large but isn't exposed at quote time. A future refinement can subtract gas
    /// once a native-token price lookup is wired in.
    func expectedNetToAmount(toCoin: Coin) -> Decimal? {
        switch self {
        case .thorchain(let quote),
             .thorchainChainnet(let quote),
             .thorchainStagenet(let quote),
             .mayachain(let quote):
            guard let raw = Decimal(string: quote.expectedAmountOut), raw > 0 else { return nil }
            return raw / toCoin.thorswapMultiplier

        case .oneinch(let quote, _),
             .kyberswap(let quote, _):
            guard let raw = BigInt(quote.dstAmount), raw > 0 else { return nil }
            return toCoin.decimal(for: raw)

        case .lifi(let quote, _, let integratorFee):
            guard let raw = BigInt(quote.dstAmount), raw > 0 else { return nil }
            let amount = toCoin.decimal(for: raw)
            let fee = amount * (integratorFee ?? 0)
            return amount - fee
        }
    }
}
