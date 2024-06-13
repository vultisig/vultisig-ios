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

    func fetchQuote(amount: Decimal, fromCoin: Coin, toCoin: Coin, isAffiliate: Bool) async throws -> SwapQuote {
        
        // 1Inch resolver
        if let fromChainID = fromCoin.chain.chainID,
           let toChainID = toCoin.chain.chainID, fromChainID == toChainID
        {
            return try await fetchOneInchQuote(
                chain: fromChainID,
                amount: amount, fromCoin: fromCoin,
                toCoin: toCoin, isAffiliate: isAffiliate
            )
        }

        // Mayachain resolver
        if mayaChains.contains(fromCoin.chain) || mayaChains.contains(toCoin.chain) {
            return try await fetchCrossChainQuote(
                provider: mayachainService,
                amount: amount,
                fromCoin: fromCoin,
                toCoin: toCoin,
                isAffiliate: isAffiliate
            )
        }

        // Thorchain resolver
        return try await fetchCrossChainQuote(
            provider: thorchainService,
            amount: amount,
            fromCoin: fromCoin,
            toCoin: toCoin,
            isAffiliate: isAffiliate
        )
    }
}

private extension SwapService {

    var mayaChains: [Chain] {
        return [.mayaChain, .kujira, .dash]
    }

    enum Errors: Error, LocalizedError {
        case swapAmountTooSmall
        case lessThenMinSwapAmount(amount: String)

        var errorDescription: String? {
            switch self {
            case .swapAmountTooSmall:
                return "Swap amount too small"
            case .lessThenMinSwapAmount(let amount):
                return "Swap amount too small. Recommended amount \(amount)"
            }
        }
    }

    func fetchCrossChainQuote(
        provider: ThorchainSwapProvider,
        amount: Decimal,
        fromCoin: Coin,
        toCoin: Coin,
        isAffiliate: Bool
    ) async throws -> SwapQuote {
        do {
            let normalizedAmount = amount * fromCoin.thorswapMultiplier
            let quote = try await provider.fetchSwapQuotes(
                address: toCoin.address,
                fromAsset: fromCoin.swapAsset,
                toAsset: toCoin.swapAsset,
                amount: normalizedAmount.description, // https://dev.thorchain.org/swap-guide/quickstart-guide.html#admonition-info-2
                interval: "1",
                isAffiliate: isAffiliate
            )

            guard let expected = Decimal(string: quote.expectedAmountOut), !expected.isZero else {
                throw Errors.swapAmountTooSmall
            }

            if let minSwapAmountDecimal = Decimal(string: quote.recommendedMinAmountIn), normalizedAmount < minSwapAmountDecimal {
                let recommendedAmount = "\(minSwapAmountDecimal / fromCoin.thorswapMultiplier) \(fromCoin.ticker)"
                throw Errors.lessThenMinSwapAmount(amount: recommendedAmount)
            }

            switch provider {
            case _ as ThorchainService:
                return .thorchain(quote)
            case _ as MayachainService:
                return .mayachain(quote)
            default:
                return .thorchain(quote)
            }
        }
        catch let error as ThorchainSwapError {
            throw error
        }
        catch let error as Errors {
            throw error
        }
        catch {
            throw Errors.swapAmountTooSmall
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
}
