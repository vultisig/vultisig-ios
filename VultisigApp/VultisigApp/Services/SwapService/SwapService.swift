//
//  SwapService.swift
//  VoltixApp
//
//  Created by Artur Guseinov on 07.05.2024.
//

import Foundation

struct SwapService {

    static let shared = SwapService()

    private let thorchainService: ThorchainService = ThorchainService.shared
    private let oneInchService: OneInchService = OneInchService.shared

    func fetchQuote(amount: Decimal, fromCoin: Coin, toCoin: Coin) async throws -> SwapQuote {
        guard let fromChainID = fromCoin.chain.chainID, let toChainID = toCoin.chain.chainID, fromChainID == toChainID else {
            return try await fetchThorchainQuote(amount: amount, fromCoin: fromCoin, toCoin: toCoin)
        }

        return try await fetchOneInchQuote(chain: fromChainID, amount: amount, fromCoin: fromCoin, toCoin: toCoin)
    }
}

private extension SwapService {

    enum Errors: String, Error, LocalizedError {
        case swapAmountTooSmall

        var errorDescription: String? {
            switch self {
            case .swapAmountTooSmall:
                return "Swap amount too small"
            }
        }
    }

    func fetchThorchainQuote(amount: Decimal, fromCoin: Coin, toCoin: Coin) async throws -> SwapQuote {
        do {
            let quote = try await thorchainService.fetchSwapQuotes(
                address: toCoin.address,
                fromAsset: fromCoin.swapAsset,
                toAsset: toCoin.swapAsset,
                amount: (amount * 100_000_000).description, // https://dev.thorchain.org/swap-guide/quickstart-guide.html#admonition-info-2
                interval: "1"
            )

            guard let expected = Decimal(string: quote.expectedAmountOut), !expected.isZero else {
                throw Errors.swapAmountTooSmall
            }

            if let minSwapAmountDecimal = quote.minSwapAmountDecimal, amount < minSwapAmountDecimal {
                throw Errors.swapAmountTooSmall
            }

            return .thorchain(quote)
        }
        catch let error as ThorchainSwapError {
            throw error
        }
        catch {
            throw Errors.swapAmountTooSmall
        }
    }

    func fetchOneInchQuote(chain: Int, amount: Decimal, fromCoin: Coin, toCoin: Coin) async throws -> SwapQuote {
        let rawAmount = fromCoin.raw(for: amount)
        let quote = try await oneInchService.fetchQuotes(
            chain: String(chain),
            source: fromCoin.contractAddress,
            destination: toCoin.contractAddress,
            amount: String(rawAmount),
            from: fromCoin.address
        )
        return .oneinch(quote)
    }
}
