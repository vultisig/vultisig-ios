//
//  SwapService.swift
//  VoltixApp
//
//  Created by Artur Guseinov on 07.05.2024.
//

import Foundation

struct SwapService {

    static let shared = SwapService()

    func fetchQuote(
        amount: Decimal,
        fromCoin: Coin,
        toCoin: Coin,
        isAffiliate: Bool,
        referredCode: String,
        vultTierDiscount: Int
    ) async throws -> SwapQuote {

        let providers = SwapCoinsResolver.resolveAllProviders(fromCoin: fromCoin, toCoin: toCoin)

        guard !providers.isEmpty else {
            throw SwapError.routeUnavailable
        }

        // Start all requests in parallel

        let tasks = providers.map { provider in
            Task {
                do {
                    let quote = try await self.fetchQuoteForProvider(
                        provider: provider,
                        amount: amount,
                        fromCoin: fromCoin,
                        toCoin: toCoin,
                        isAffiliate: isAffiliate,
                        referredCode: referredCode,
                        vultTierDiscount: vultTierDiscount
                    )
                    return Result<SwapQuote, Error>.success(quote)
                } catch {
                    return Result<SwapQuote, Error>.failure(error)
                }
            }
        }

        var lastError: Error?

        // Await results in priority order
        for task in tasks {
            switch await task.value {
            case .success(let quote):
                // Found a successful quote from the highest priority provider available
                // Cancel remaining tasks to save resources
                tasks.forEach { $0.cancel() }
                return quote
            case .failure(let error):
                // This provider failed, try the next one (which is already running)
                lastError = error
                continue
            }
        }

        throw lastError ?? SwapError.routeUnavailable
    }

    private func fetchQuoteForProvider(
        provider: SwapProvider,
        amount: Decimal,
        fromCoin: Coin,
        toCoin: Coin,
        isAffiliate: Bool,
        referredCode: String,
        vultTierDiscount: Int,
    ) async throws -> SwapQuote {
        switch provider {
        case .thorchain:
            return try await fetchCrossChainQuote(
                service: ThorchainService.shared,
                provider: provider,
                amount: amount,
                fromCoin: fromCoin,
                toCoin: toCoin,
                referredCode: referredCode,
                vultTierDiscount: vultTierDiscount
            )
        case .thorchainChainnet:
            return try await fetchCrossChainQuote(
                service: ThorchainChainnetService.shared,
                provider: provider,
                amount: amount,
                fromCoin: fromCoin,
                toCoin: toCoin,
                referredCode: referredCode,
                vultTierDiscount: vultTierDiscount
            )
        case .thorchainStagenet2:
            return try await fetchCrossChainQuote(
                service: ThorchainStagenet2Service.shared,
                provider: provider,
                amount: amount,
                fromCoin: fromCoin,
                toCoin: toCoin,
                referredCode: referredCode,
                vultTierDiscount: vultTierDiscount
            )
        case .mayachain:
            return try await fetchCrossChainQuote(
                service: MayachainService.shared,
                provider: provider,
                amount: amount,
                fromCoin: fromCoin,
                toCoin: toCoin,
                referredCode: referredCode,
                vultTierDiscount: vultTierDiscount
            )
        case .oneinch:
            guard let fromChainID = fromCoin.chain.chainID,
                  let toChainID = toCoin.chain.chainID, fromChainID == toChainID else {
                  throw SwapError.routeUnavailable
            }
            return try await fetchOneInchQuote(
                service: OneInchService.shared,
                chain: fromChainID,
                amount: amount,
                fromCoin: fromCoin,
                toCoin: toCoin,
                isAffiliate: isAffiliate,
                vultTierDiscount: vultTierDiscount
            )
        case .kyberswap:
            guard let fromChainID = fromCoin.chain.chainID,
                  let toChainID = toCoin.chain.chainID, fromChainID == toChainID else {
                  throw SwapError.routeUnavailable
            }
            return try await fetchKyberSwapQuote(
                service: KyberSwapService.shared,
                chain: try KyberSwapService.shared.getChainName(for: fromCoin.chain),
                amount: amount,
                fromCoin: fromCoin,
                toCoin: toCoin,
                isAffiliate: isAffiliate
            )
        case .lifi:
            return try await fetchLiFiQuote(
                service: LiFiService.shared,
                amount: amount,
                fromCoin: fromCoin,
                toCoin: toCoin,
                vultTierDiscount: vultTierDiscount
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
        referredCode: String,
        vultTierDiscount: Int
    ) async throws -> SwapQuote {
        do {
            /// https://dev.thorchain.org/swap-guide/quickstart-guide.html#admonition-info-2
            let normalizedAmount = amount * fromCoin.thorswapMultiplier
            // THORChain expects integer amounts - truncate any floating point residuals
            let truncatedAmount = normalizedAmount.truncated(toPlaces: 0)

            let quote = try await service.fetchSwapQuotes(
                address: toCoin.address,
                fromAsset: fromCoin.swapAsset,
                toAsset: toCoin.swapAsset,
                amount: truncatedAmount.description,
                interval: provider.streamingInterval,
                referredCode: referredCode,
                vultTierDiscount: vultTierDiscount
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
            case _ as ThorchainChainnetService:
                return .thorchainChainnet(quote)
            case _ as ThorchainStagenet2Service:
                return .thorchainStagenet2(quote)
            case _ as MayachainService:
                return .mayachain(quote)
            default:
                return .thorchain(quote)
            }
        } catch let error as ThorchainSwapError {
            print("❌ [COSMOS DEBUG] THORChain error: code=\(error.code), message=\(error.message)")
            if error.code == 3 {
                if error.message.contains("not enough asset to pay for fees") {
                    throw SwapError.swapAmountTooSmall
                } else if error.message.localizedCaseInsensitiveContains("invalid symbol") ||
                          error.message.localizedCaseInsensitiveContains("bad to asset") ||
                          error.message.localizedCaseInsensitiveContains("bad from asset") {
                    // This typically means no liquidity pool exists for this token pair
                    throw SwapError.noLiquidityPool
                } else {
                    throw SwapError.serverError(message: error.message)
                }
            } else {
                throw SwapError.routeUnavailable
            }
        } catch let error as MayachainSwapError {
            throw SwapError.serverError(message: error.error)
        } catch let error as SwapError {
            throw error
        } catch {
            throw SwapError.swapAmountTooSmall
        }
    }

    func fetchOneInchQuote(
        service: OneInchService,
        chain: Int,
        amount: Decimal,
        fromCoin: Coin,
        toCoin: Coin,
        isAffiliate: Bool,
        vultTierDiscount: Int
    ) async throws -> SwapQuote {
        let rawAmount = fromCoin.raw(for: amount)
        let response = try await service.fetchQuotes(
            chain: String(chain),
            source: fromCoin.contractAddress,
            destination: toCoin.contractAddress,
            amount: String(rawAmount),
            from: fromCoin.address,
            isAffiliate: isAffiliate,
            vultTierDiscount: vultTierDiscount
        )
        return .oneinch(response.quote, fee: response.fee)
    }

    func fetchKyberSwapQuote(
        service: KyberSwapService,
        chain: String,
        amount: Decimal,
        fromCoin: Coin,
        toCoin: Coin,
        isAffiliate: Bool
    ) async throws -> SwapQuote {
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

    func fetchLiFiQuote(
        service: LiFiService,
        amount: Decimal,
        fromCoin: Coin,
        toCoin: Coin,
        vultTierDiscount: Int
    ) async throws -> SwapQuote {
        let fromAmount = fromCoin.raw(for: amount)
        let response = try await service.fetchQuotes(
            fromCoin: fromCoin,
            toCoin: toCoin,
            fromAmount: fromAmount,
            vultTierDiscount: vultTierDiscount
        )
        print("LiFi Quote: \(response.quote)")
        return .lifi(response.quote, fee: response.fee, integratorFee: response.integratorFee)
    }
}
