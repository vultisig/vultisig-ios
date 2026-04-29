//
//  SwapQuote+Ranking.swift
//  VultisigApp
//

import Foundation
import BigInt

extension SwapQuote {

    /// Expected output amount in `toCoin` units, net of provider/inbound/outbound fees.
    /// THORChain/Maya: `expectedAmountOut` is already net of inbound + swap + outbound fees.
    /// LiFi/1inch/KyberSwap: `dstAmount` is the swapped amount; LiFi additionally subtracts the
    /// integrator fee that is charged on the output side.
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

    /// Source-chain gas cost in `fromCoin` native units, when estimable from the quote.
    /// Aggregator quotes carry `gas`/`gasPrice` directly. THORChain Router deposits on EVM are
    /// estimated via the project's standard swap gas constant (matches how 1inch/Kyber/LiFi normalize
    /// missing gas). For non-EVM source chains the gas is paid in the native coin and is not exposed
    /// at quote time, so we return `nil` and skip gas in the comparison.
    func sourceChainGasInNative(fromCoin: Coin) -> Decimal? {
        switch self {
        case .oneinch(let quote, _),
             .kyberswap(let quote, _),
             .lifi(let quote, _, _):
            guard fromCoin.chain.chainType == .EVM else { return nil }
            return evmGasInNative(gas: quote.tx.gas, gasPrice: quote.tx.gasPrice, fromCoin: fromCoin)

        case .thorchain, .thorchainChainnet, .thorchainStagenet, .mayachain:
            // THORChain/Maya only have an EVM-side gas cost when the source chain is EVM
            // (Router `depositWithExpiry`). For non-EVM source chains the gas is paid in the
            // native coin and is not exposed at quote time.
            guard fromCoin.chain.chainType == .EVM else { return nil }
            // No gasPrice in THORChain quotes — we can't quantify the EVM Router gas at quote time
            // without an extra RPC call. Returning nil keeps THORChain comparable on net output
            // alone; ranking still penalizes it whenever an aggregator's net output is higher.
            return nil
        }
    }

    /// Comparable net value of the quote, in fiat. Subtracts source-chain gas when available.
    /// Returns `nil` if either the destination price or destination amount can't be resolved —
    /// in that case callers should fall back to ranking by `expectedNetToAmount`.
    func rankableFiatValue(fromCoin: Coin, toCoin: Coin) -> Decimal? {
        guard let netToAmount = expectedNetToAmount(toCoin: toCoin) else { return nil }

        let outFiat = RateProvider.shared.fiatBalance(value: netToAmount, coin: toCoin)
        guard outFiat > 0 else { return nil }

        if let gasNative = sourceChainGasInNative(fromCoin: fromCoin) {
            let gasFiat = RateProvider.shared.fiatBalance(value: gasNative, coin: fromCoin)
            return outFiat - gasFiat
        }

        return outFiat
    }

    private func evmGasInNative(gas: Int64, gasPrice: String, fromCoin _: Coin) -> Decimal? {
        let normalizedGas = gas == 0 ? EVMHelper.defaultETHSwapGasUnit : gas
        guard let gasPriceWei = BigInt(gasPrice), gasPriceWei > 0 else { return nil }
        let totalWei = gasPriceWei * BigInt(normalizedGas)
        // Gas is always denominated in the chain's native token (18 decimals on EVM)
        return Decimal(string: totalWei.description).map { $0 / pow(Decimal(10), 18) }
    }
}
