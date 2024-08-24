//
//  SwapService.swift
//  VoltixApp
//
//  Created by Artur Guseinov on 07.05.2024.
//

import Foundation

struct SwapService {

    static let shared = SwapService()

    private let thorchainService: ThorchainSwapProvider = ThorchainService.shared
    private let mayachainService: ThorchainSwapProvider = MayachainService.shared
    private let oneInchService: OneInchService = OneInchService.shared
    private let lifiService: LiFiService = LiFiService.shared

    func fetchQuote(amount: Decimal, fromCoin: Coin, toCoin: Coin, isAffiliate: Bool) async throws -> SwapQuote {

        guard let provider = SwapCoinsResolver.resolveProvider(fromCoin: fromCoin, toCoin: toCoin) else {
            throw SwapError.routeUnavailable
        }

        switch provider {
        case .thorchain:
            return try await fetchCrossChainQuote(
                service: thorchainService, 
                provider: provider,
                amount: amount,
                fromCoin: fromCoin,
                toCoin: toCoin,
                isAffiliate: isAffiliate
            )
        case .mayachain:
            return try await fetchCrossChainQuote(
                service: mayachainService,
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
                chain: fromChainID,
                amount: amount, fromCoin: fromCoin,
                toCoin: toCoin, isAffiliate: isAffiliate
            )
        case .lifi:
            return try await fetchLiFiQuote(
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
        catch _ as ThorchainSwapError {
            throw SwapError.routeUnavailable
        }
        catch let error as SwapError {
            throw error
        }
        catch {
            throw SwapError.swapAmountTooSmall
        }
    }

    func fetchOneInchQuote(chain: Int, amount: Decimal, fromCoin: Coin, toCoin: Coin, isAffiliate: Bool) async throws -> SwapQuote {
        let rawAmount = fromCoin.raw(for: amount)
        let quote = try await oneInchService.fetchQuotes(
            chain: String(chain),
            source: fromCoin.contractAddress,
            destination: toCoin.contractAddress,
            amount: String(rawAmount),
            from: fromCoin.address,
            isAffiliate: isAffiliate
        )
        return .oneinch(quote)
    }

    func fetchLiFiQuote(amount: Decimal, fromCoin: Coin, toCoin: Coin, isAffiliate: Bool) async throws -> SwapQuote {
        let fromAmount = fromCoin.raw(for: amount)
        let quote = try await lifiService.fetchQuotes(
            fromCoin: fromCoin,
            toCoin: toCoin,
            fromAmount: fromAmount
        )
        return .lifi(quote)
    }
}
