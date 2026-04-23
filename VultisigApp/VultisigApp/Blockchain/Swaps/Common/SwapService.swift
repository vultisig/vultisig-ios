//
//  SwapService.swift
//  VoltixApp
//
//  Created by Artur Guseinov on 07.05.2024.
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "swap-service")

struct SwapService {
    static let shared = SwapService()

    /// Fall back from rapid to streaming THORChain swap when rapid slippage
    /// (`fees.total` share of output) exceeds this threshold. 300 bps = 3%.
    static let streamingSlippageThresholdBps = 300

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
            case let .success(quote):
                // Found a successful quote from the highest priority provider available
                // Cancel remaining tasks to save resources
                tasks.forEach { $0.cancel() }
                return quote
            case let .failure(error):
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
        vultTierDiscount: Int
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
        case .thorchainStagenet:
            return try await fetchCrossChainQuote(
                service: ThorchainStagenetService.shared,
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
                  let toChainID = toCoin.chain.chainID, fromChainID == toChainID
            else {
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
                  let toChainID = toCoin.chain.chainID, fromChainID == toChainID
            else {
                throw SwapError.routeUnavailable
            }
            return try await fetchKyberSwapQuote(
                service: KyberSwapService.shared,
                chain: KyberSwapService.shared.getChainName(for: fromCoin.chain),
                amount: amount,
                fromCoin: fromCoin,
                toCoin: toCoin,
                vultTierDiscount: vultTierDiscount
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
            // https://dev.thorchain.org/swap-guide/quickstart-guide.html#admonition-info-2
            let normalizedAmount = amount * fromCoin.thorswapMultiplier
            // THORChain expects integer amounts - truncate any floating point residuals
            let truncatedAmount = normalizedAmount.truncated(toPlaces: 0)

            let rapidQuote = try await service.fetchSwapQuotes(
                address: toCoin.address,
                fromAsset: fromCoin.swapAsset,
                toAsset: toCoin.swapAsset,
                amount: truncatedAmount.description,
                interval: provider.streamingInterval,
                referredCode: referredCode,
                vultTierDiscount: vultTierDiscount
            )

            guard let expected = Decimal(string: rapidQuote.expectedAmountOut), !expected.isZero else {
                throw SwapError.swapAmountTooSmall
            }

            if let minSwapAmountDecimal = Decimal(string: rapidQuote.recommendedMinAmountIn), normalizedAmount < minSwapAmountDecimal {
                let recommendedAmount = "\(minSwapAmountDecimal / fromCoin.thorswapMultiplier) \(fromCoin.ticker)"
                throw SwapError.lessThenMinSwapAmount(amount: recommendedAmount)
            }

            let quote = await maybeUpgradeToStreaming(
                rapid: rapidQuote,
                service: service,
                provider: provider,
                address: toCoin.address,
                fromAsset: fromCoin.swapAsset,
                toAsset: toCoin.swapAsset,
                amount: truncatedAmount.description,
                referredCode: referredCode,
                vultTierDiscount: vultTierDiscount
            )

            switch service {
            case _ as ThorchainService:
                return .thorchain(quote)
            case _ as ThorchainChainnetService:
                return .thorchainChainnet(quote)
            case _ as ThorchainStagenetService:
                return .thorchainStagenet(quote)
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
                    error.message.localizedCaseInsensitiveContains("bad from asset") ||
                    error.message.localizedCaseInsensitiveContains("pool does not exist") {
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
        vultTierDiscount: Int
    ) async throws -> SwapQuote {
        let affiliateBps = vultTierDiscount >= 50 ? 0 : 50 - vultTierDiscount
        let rawAmount = fromCoin.raw(for: amount)
        let (quote, fee) = try await service.fetchQuotes(
            chain: chain,
            source: fromCoin.isNativeToken ? "" : fromCoin.contractAddress,
            destination: toCoin.isNativeToken ? "" : toCoin.contractAddress,
            amount: String(rawAmount),
            from: fromCoin.address,
            affiliateBps: affiliateBps
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

// MARK: - THORChain anti-rekt streaming fallback

extension SwapService {
    /// Slippage in basis points from a THORChain rapid quote. Prefers the
    /// authoritative `fees.total_bps` returned by the node, computed as
    /// `total × 10_000 / (expected_amount_out + total)`. Falls back to the
    /// same formula locally when the field is absent (older nodes, Maya).
    ///
    /// Returns `nil` when inputs cannot be parsed; callers should treat that
    /// as "do not trigger streaming".
    static func rapidSlippageBps(fromQuote quote: ThorchainSwapQuote) -> Int? {
        if let totalBps = quote.fees.totalBps {
            return totalBps
        }

        guard let feesTotal = Double(quote.fees.total),
              let expected = Double(quote.expectedAmountOut) else {
            return nil
        }

        let gross = feesTotal + expected
        guard gross > 0, feesTotal > 0 else { return 0 }

        return Int((feesTotal * 10_000) / gross)
    }

    /// Pick the better quote between rapid and streaming. Returns streaming only
    /// when its `expected_amount_out` is strictly greater than rapid's.
    static func selectBetterQuote(
        rapid: ThorchainSwapQuote,
        streaming: ThorchainSwapQuote
    ) -> ThorchainSwapQuote {
        guard let rapidOut = Decimal(string: rapid.expectedAmountOut),
              let streamingOut = Decimal(string: streaming.expectedAmountOut) else {
            return rapid
        }
        return streamingOut > rapidOut ? streaming : rapid
    }

    /// Only THORChain providers opt into streaming fallback. Maya is excluded
    /// (different liquidity profile; separate ticket if parity is wanted).
    static func supportsStreamingFallback(_ provider: SwapProvider) -> Bool {
        switch provider {
        case .thorchain, .thorchainChainnet, .thorchainStagenet:
            return true
        case .mayachain, .oneinch, .kyberswap, .lifi:
            return false
        }
    }
}

extension SwapService {
    func maybeUpgradeToStreaming(
        rapid: ThorchainSwapQuote,
        service: ThorchainSwapProvider,
        provider: SwapProvider,
        address: String,
        fromAsset: String,
        toAsset: String,
        amount: String,
        referredCode: String,
        vultTierDiscount: Int
    ) async -> ThorchainSwapQuote {
        guard Self.supportsStreamingFallback(provider) else {
            logger.info("[anti-rekt] provider=\(String(describing: provider), privacy: .public) not eligible → using RAPID")
            return rapid
        }

        let slippageBps = Self.rapidSlippageBps(fromQuote: rapid) ?? 0
        logger.info("[anti-rekt] rapid slippage=\(slippageBps, privacy: .public) bps, threshold=\(Self.streamingSlippageThresholdBps, privacy: .public) bps, fromAsset=\(fromAsset, privacy: .public), toAsset=\(toAsset, privacy: .public)")

        guard slippageBps > Self.streamingSlippageThresholdBps else {
            logger.info("[anti-rekt] slippage ≤ threshold → using RAPID (memo=\(rapid.memo, privacy: .public))")
            return rapid
        }

        let streamingQuantity = rapid.maxStreamingQuantity ?? 0
        guard streamingQuantity > 0 else {
            logger.info("[anti-rekt] max_streaming_quantity missing/zero → using RAPID")
            return rapid
        }

        logger.info("[anti-rekt] fetching STREAMING quote (interval=1, quantity=\(streamingQuantity, privacy: .public))")

        do {
            let streaming = try await service.fetchSwapQuotes(
                address: address,
                fromAsset: fromAsset,
                toAsset: toAsset,
                amount: amount,
                interval: 1,
                streamingQuantity: streamingQuantity,
                referredCode: referredCode,
                vultTierDiscount: vultTierDiscount
            )
            let chosen = Self.selectBetterQuote(rapid: rapid, streaming: streaming)
            let pickedStreaming = chosen.expectedAmountOut == streaming.expectedAmountOut &&
                chosen.expectedAmountOut != rapid.expectedAmountOut
            logger.info("[anti-rekt] rapid out=\(rapid.expectedAmountOut, privacy: .public), streaming out=\(streaming.expectedAmountOut, privacy: .public) → using \(pickedStreaming ? "STREAMING" : "RAPID", privacy: .public) (memo=\(chosen.memo, privacy: .public))")
            return chosen
        } catch {
            logger.warning("[anti-rekt] streaming fetch failed, falling back to RAPID: \(error.localizedDescription, privacy: .public)")
            return rapid
        }
    }
}
