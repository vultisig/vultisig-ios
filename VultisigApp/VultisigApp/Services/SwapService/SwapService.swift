//
//  SwapService.swift
//  VoltixApp
//
//  Created by Artur Guseinov on 07.05.2024.
//

import Foundation

struct SwapService {

    static let shared = SwapService()
    
    func fetchQuote(amount: Decimal, fromCoin: Coin, toCoin: Coin, isAffiliate: Bool) async throws -> SwapQuote {

        guard let provider = SwapCoinsResolver.resolveProvider(fromCoin: fromCoin, toCoin: toCoin) else {
            throw SwapError.routeUnavailable
        }

        switch provider {
        case .thorchain:
            return try await fetchCrossChainQuote(
                service: ThorchainService.shared, 
                provider: provider,
                amount: amount,
                fromCoin: fromCoin,
                toCoin: toCoin,
                isAffiliate: isAffiliate
            )
        case .mayachain:
            return try await fetchCrossChainQuote(
                service: MayachainService.shared,
                provider: provider,
                amount: amount,
                fromCoin: fromCoin,
                toCoin: toCoin,
                isAffiliate: isAffiliate
            )
        case .oneinch:
            guard let fromChainID = fromCoin.chain.chainID,
                  let toChainID = toCoin.chain.chainID, fromChainID == toChainID else {
                  throw SwapError.routeUnavailable
            }
            return try await fetchOneInchQuote(
                service: OneInchService.shared,
                chain: fromChainID,
                amount: amount, fromCoin: fromCoin,
                toCoin: toCoin, isAffiliate: isAffiliate
            )
        case .kyberswap(_):
            guard let fromChainID = fromCoin.chain.chainID,
                  let toChainID = toCoin.chain.chainID, fromChainID == toChainID else {
                  throw SwapError.routeUnavailable
            }
            return try await fetchKyberSwapQuote(
                service: KyberSwapService.shared,
                chain: try KyberSwapService.shared.getChainName(for: fromCoin.chain),
                amount: amount,
                fromCoin: fromCoin,
                toCoin: toCoin, isAffiliate: isAffiliate
            )
        case .lifi:
            return try await fetchLiFiQuote(
                service: LiFiService.shared,
                amount: amount, fromCoin: fromCoin,
                toCoin: toCoin, isAffiliate: isAffiliate
            )
        }
    }
}

private extension SwapService {

    func fetchCrossChainQuote(
        service: ThorchainSwapProvider,
        provider: SwapProvider,
        amount: Decimal,
        fromCoin: Coin,
        toCoin: Coin,
        isAffiliate: Bool
    ) async throws -> SwapQuote {
        do {
            /// https://dev.thorchain.org/swap-guide/quickstart-guide.html#admonition-info-2
            let normalizedAmount = amount * fromCoin.thorswapMultiplier
            
            let quote = try await service.fetchSwapQuotes(
                address: toCoin.address,
                fromAsset: fromCoin.swapAsset,
                toAsset: toCoin.swapAsset,
                amount: normalizedAmount.description,
                interval: provider.streamingInterval,
                isAffiliate: isAffiliate
            )

            guard let expected = Decimal(string: quote.expectedAmountOut), !expected.isZero else {
                throw SwapError.swapAmountTooSmall
            }

            if let minSwapAmountDecimal = Decimal(string: quote.recommendedMinAmountIn), normalizedAmount < minSwapAmountDecimal {
                let recommendedAmount = "\(minSwapAmountDecimal / fromCoin.thorswapMultiplier) \(fromCoin.ticker)"
                throw SwapError.lessThenMinSwapAmount(amount: recommendedAmount)
            }

            switch service {
            case _ as ThorchainService:
                return .thorchain(quote)
            case _ as MayachainService:
                return .mayachain(quote)
            default:
                return .thorchain(quote)
            }
        }
        catch let error as ThorchainSwapError {
            if error.message.contains("not enough asset to pay for fees") {
                throw SwapError.swapAmountTooSmall
            } else {
                throw SwapError.routeUnavailable
            }
        }
        catch let error as SwapError {
            throw error
        }
        catch {
            throw SwapError.swapAmountTooSmall
        }
    }

    func fetchOneInchQuote(service: OneInchService, chain: Int, amount: Decimal, fromCoin: Coin, toCoin: Coin, isAffiliate: Bool) async throws -> SwapQuote {
        let rawAmount = fromCoin.raw(for: amount)
        let response = try await service.fetchQuotes(
            chain: String(chain),
            source: fromCoin.contractAddress,
            destination: toCoin.contractAddress,
            amount: String(rawAmount),
            from: fromCoin.address,
            isAffiliate: isAffiliate
        )
        return .oneinch(response.quote, fee: response.fee)
    }
    
    func fetchKyberSwapQuote(service: KyberSwapService, chain: String, amount: Decimal, fromCoin: Coin, toCoin: Coin, isAffiliate: Bool) async throws -> SwapQuote {
        let rawAmount = fromCoin.raw(for: amount)
        let (quote, fee) = try await service.fetchQuotes(
            chain: chain,
            source: fromCoin.isNativeToken ? "" : fromCoin.contractAddress,
            destination: toCoin.isNativeToken ? "" : toCoin.contractAddress,
            amount: String(rawAmount),
            from: fromCoin.address,
            isAffiliate: isAffiliate
        )
        return .kyberswap(quote, fee: fee)
    }
    
    func fetchLiFiQuote(service: LiFiService, amount: Decimal, fromCoin: Coin, toCoin: Coin, isAffiliate: Bool) async throws -> SwapQuote {
        let fromAmount = fromCoin.raw(for: amount)
        let response = try await service.fetchQuotes(
            fromCoin: fromCoin,
            toCoin: toCoin,
            fromAmount: fromAmount
        )
        return .lifi(response.quote, fee: response.fee)
    }
}
