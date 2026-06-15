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
    /// (`fees.total` share of output) exceeds this threshold. 100 bps = 1%.
    /// Streaming typically drops slippage from ~41 bps to ~9 bps on trades
    /// it covers; a 1% cutoff captures mid-size cross-chain swaps that
    /// otherwise route via rapid despite being good streaming candidates.
    /// Mirrored in `vultisig-sdk` (`THORCHAIN_STREAMING_SLIPPAGE_THRESHOLD_BPS`)
    /// and `vultisig-android` (`STREAMING_SLIPPAGE_THRESHOLD_BPS`).
    static let streamingSlippageThresholdBps = 100

    /// Minimum-output tolerance (basis points) sent on every THORChain/Maya
    /// quote request as `tolerance_bps`. The node bakes a real `LIM` into the
    /// returned swap memo — `expected_amount_out × (1 − tolerance_bps/10_000)` —
    /// so the signed memo carries a slippage floor instead of `LIM=0`
    /// (unbounded). 100 bps (1%) is a conservative default aligned with the
    /// streaming-upgrade threshold; there is no per-swap user slippage control.
    static let defaultThorchainToleranceBps = 100

    func fetchQuote(
        amount: Decimal,
        fromCoin: Coin,
        toCoin: Coin,
        isAffiliate: Bool,
        referredCode: String,
        vultTierDiscount: Int
    ) async throws -> SwapQuote {
        try await fetchQuotes(
            amount: amount,
            fromCoin: fromCoin,
            toCoin: toCoin,
            isAffiliate: isAffiliate,
            referredCode: referredCode,
            vultTierDiscount: vultTierDiscount,
            slippageBps: nil,
            recipientAddress: nil
        ).best
    }

    /// Fetch every eligible provider in parallel and return the full ranked set alongside the
    /// auto-selected winner. The winner is still chosen by `selectBestQuote` (net output + banded
    /// provider preference); `ranked` is the same candidate pool sorted best→worst by
    /// `expectedNetToAmount` so the UI can surface alternatives without re-fetching.
    ///
    /// Returning on first success would honour the priority order baked into `resolveAllProviders`,
    /// which is fine when only one provider is eligible but produces poor outcomes on same-chain
    /// ERC20 routes where THORChain is listed first yet routes through its Router with a costly
    /// `depositWithExpiry` deposit and a destination amount that's typically lower than what an
    /// aggregator returns.
    func fetchQuotes(
        amount: Decimal,
        fromCoin: Coin,
        toCoin: Coin,
        isAffiliate: Bool,
        referredCode: String,
        vultTierDiscount: Int,
        slippageBps: Int?,
        recipientAddress: String?
    ) async throws -> SwapQuotes {
        let providers = SwapCoinsResolver.resolveAllProviders(fromCoin: fromCoin, toCoin: toCoin)

        guard !providers.isEmpty else {
            throw SwapError.routeUnavailable
        }

        let results = await withTaskGroup(of: Result<SwapQuote, Error>.self) { group in
            for provider in providers {
                group.addTask {
                    do {
                        let quote = try await self.fetchQuoteForProvider(
                            provider: provider,
                            amount: amount,
                            fromCoin: fromCoin,
                            toCoin: toCoin,
                            isAffiliate: isAffiliate,
                            referredCode: referredCode,
                            vultTierDiscount: vultTierDiscount,
                            slippageBps: slippageBps,
                            recipientAddress: recipientAddress
                        )
                        return Result<SwapQuote, Error>.success(quote)
                    } catch {
                        return Result<SwapQuote, Error>.failure(error)
                    }
                }
            }

            var collected: [Result<SwapQuote, Error>] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        let quotes = results.compactMap { try? $0.get() }
        if let best = Self.selectBestQuote(quotes: quotes, toCoin: toCoin) {
            let ranked = Self.rankedQuotes(quotes: quotes, toCoin: toCoin)
            // Preserve the `best ∈ ranked` contract: if nothing is rankable (no
            // comparable net amounts) but a best still exists, surface it.
            return SwapQuotes(best: best, ranked: ranked.isEmpty ? [best] : ranked)
        }

        let firstError = results.compactMap { result -> Error? in
            if case .failure(let error) = result { return error }
            return nil
        }.first

        throw firstError ?? SwapError.routeUnavailable
    }

    /// All rankable quotes sorted best→worst by net output in `toCoin` units — the same metric
    /// `selectBestQuote` ranks on, so the first element matches the winner on a pure-rate basis.
    /// Quotes that can't produce a comparable net amount are dropped (they can't be ranked).
    /// Provider preference (the banded layer in `selectBestQuote`) intentionally does *not* reorder
    /// this list: the user-facing list shows raw rate order so the displayed amounts are monotonic.
    static func rankedQuotes(quotes: [SwapQuote], toCoin: Coin) -> [SwapQuote] {
        quotes
            .compactMap { quote -> (SwapQuote, Decimal)? in
                guard let value = quote.expectedNetToAmount(toCoin: toCoin) else { return nil }
                return (quote, value)
            }
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
    }

    /// Width of the priority band, as a fraction of the best net output. Quotes whose net
    /// output lands within this band of the best are treated as effectively tied on rate, so
    /// the higher-priority provider is preferred over a marginally larger raw output. 1%.
    static let providerPreferenceBand: Decimal = 0.01

    /// Pick the best quote across providers. The ranking metric is net output in `toCoin`
    /// units (every provider in a candidate set swaps to the same `toCoin`, so the
    /// destination amount is directly comparable). On top of that metric a banded
    /// provider-preference layer applies: among quotes within `providerPreferenceBand` (1%)
    /// of the best net output, the highest-priority provider wins instead of the raw maximum.
    /// This keeps near-tie routes on the more trusted/integrated provider without ever
    /// trading away a materially better rate (anything outside the band loses on output).
    /// Falls back to the first quote (priority order from `resolveAllProviders`) when no
    /// quote produces a comparable amount.
    ///
    /// iOS is the cross-platform anchor for this rule; the canonical spec lives in
    /// `vultisig-sdk` and other platforms mirror this implementation.
    static func selectBestQuote(
        quotes: [SwapQuote],
        toCoin: Coin
    ) -> SwapQuote? {
        guard !quotes.isEmpty else { return nil }

        let ranked = quotes.compactMap { quote -> (SwapQuote, Decimal)? in
            guard let value = quote.expectedNetToAmount(toCoin: toCoin) else { return nil }
            return (quote, value)
        }

        guard let best = ranked.max(by: { $0.1 < $1.1 }) else {
            logger.warning("[swap-rank] no quote was rankable, returning first by priority")
            return quotes.first
        }

        // Quotes within the band of the best net output are treated as tied on rate; among
        // those, prefer the higher-priority (lower index) provider. Tie-break inside the same
        // priority by higher net output (defensive — a provider rarely appears twice).
        let floor = best.1 * (1 - providerPreferenceBand)
        let inBand = ranked.filter { $0.1 >= floor }
        let picked = inBand.min { lhs, rhs in
            let lhsPriority = priority(of: lhs.0)
            let rhsPriority = priority(of: rhs.0)
            if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
            return lhs.1 > rhs.1
        } ?? best

        let summary = ranked
            .map { "\($0.0.displayName ?? "?")=\($0.1)" }
            .joined(separator: ", ")
        let inBandSummary = inBand
            .map { "\($0.0.displayName ?? "?")=\($0.1)(p\(priority(of: $0.0)))" }
            .joined(separator: ", ")
        logger.info("[swap-rank] candidates=\(quotes.count, privacy: .public) [\(summary, privacy: .public)] best=\(best.0.displayName ?? "?", privacy: .public)=\(best.1, privacy: .public) floor=\(floor, privacy: .public) inBand=[\(inBandSummary, privacy: .public)] → \(picked.0.displayName ?? "?", privacy: .public)")
        return picked.0
    }

    /// Provider preference order for the banded selection. Lower index = preferred. Keyed off
    /// the enum case (not `displayName`, which can carry SwapKit sub-provider text). THORChain
    /// (all networks) is most preferred, then Maya, SwapKit, KyberSwap, 1inch, LI.FI.
    private static func priority(of quote: SwapQuote) -> Int {
        switch quote {
        case .thorchain, .thorchainChainnet, .thorchainStagenet:
            return 0
        case .mayachain:
            return 1
        case .swapkit:
            return 2
        case .kyberswap:
            return 3
        case .oneinch:
            return 4
        case .lifi:
            return 5
        }
    }

    private func fetchQuoteForProvider(
        provider: SwapProvider,
        amount: Decimal,
        fromCoin: Coin,
        toCoin: Coin,
        isAffiliate: Bool,
        referredCode: String,
        vultTierDiscount: Int,
        slippageBps: Int?,
        recipientAddress: String?
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
                vultTierDiscount: vultTierDiscount,
                slippageBps: slippageBps,
                recipientAddress: recipientAddress
            )
        case .thorchainChainnet:
            return try await fetchCrossChainQuote(
                service: ThorchainChainnetService.shared,
                provider: provider,
                amount: amount,
                fromCoin: fromCoin,
                toCoin: toCoin,
                referredCode: referredCode,
                vultTierDiscount: vultTierDiscount,
                slippageBps: slippageBps,
                recipientAddress: recipientAddress
            )
        case .thorchainStagenet:
            return try await fetchCrossChainQuote(
                service: ThorchainStagenetService.shared,
                provider: provider,
                amount: amount,
                fromCoin: fromCoin,
                toCoin: toCoin,
                referredCode: referredCode,
                vultTierDiscount: vultTierDiscount,
                slippageBps: slippageBps,
                recipientAddress: recipientAddress
            )
        case .mayachain:
            return try await fetchCrossChainQuote(
                service: MayachainService.shared,
                provider: provider,
                amount: amount,
                fromCoin: fromCoin,
                toCoin: toCoin,
                referredCode: referredCode,
                vultTierDiscount: vultTierDiscount,
                slippageBps: slippageBps,
                recipientAddress: recipientAddress
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
                vultTierDiscount: vultTierDiscount,
                slippageBps: slippageBps
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
                vultTierDiscount: vultTierDiscount,
                slippageBps: slippageBps
            )
        case .lifi:
            return try await fetchLiFiQuote(
                service: LiFiService.shared,
                amount: amount,
                fromCoin: fromCoin,
                toCoin: toCoin,
                vultTierDiscount: vultTierDiscount,
                slippageBps: slippageBps
            )
        case .swapkit:
            return try await fetchSwapKitQuote(
                service: SwapKitService.shared,
                amount: amount,
                fromCoin: fromCoin,
                toCoin: toCoin,
                vultTierDiscount: vultTierDiscount,
                slippageBps: slippageBps
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
        vultTierDiscount: Int,
        slippageBps: Int?,
        recipientAddress: String?
    ) async throws -> SwapQuote {
        do {
            // https://dev.thorchain.org/swap-guide/quickstart-guide.html#admonition-info-2
            let normalizedAmount = amount * fromCoin.thorswapMultiplier
            // THORChain expects integer amounts - truncate any floating point residuals
            let truncatedAmount = normalizedAmount.truncated(toPlaces: 0)

            // `Auto` (nil) keeps the conservative default tolerance; a custom
            // slippage maps directly to `tolerance_bps`, which the node bakes
            // into the returned memo's `LIM` floor.
            let toleranceBps = slippageBps ?? Self.defaultThorchainToleranceBps

            // External recipient (when set) becomes the swap's `destination` — the
            // node encodes it into the returned memo, so the swapped funds land at
            // the external address instead of the user's own. Defaults to the
            // user's own destination address.
            let destination = recipientAddress ?? toCoin.address

            let rapidQuote = try await service.fetchSwapQuotes(
                address: destination,
                fromAsset: fromCoin.swapAsset,
                toAsset: toCoin.swapAsset,
                amount: truncatedAmount.description,
                interval: provider.streamingInterval,
                toleranceBps: toleranceBps,
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
                address: destination,
                fromAsset: fromCoin.swapAsset,
                toAsset: toCoin.swapAsset,
                amount: truncatedAmount.description,
                referredCode: referredCode,
                vultTierDiscount: vultTierDiscount,
                toleranceBps: toleranceBps
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
            logger.error("THORChain swap error: code=\(error.code, privacy: .public), message=\(error.message, privacy: .public)")
            throw Self.mapThorchainSwapError(error)
        } catch let error as MayachainSwapError {
            logger.error("MAYAChain swap error: code=\(error.code ?? -1, privacy: .public), message=\(error.error, privacy: .public)")
            throw Self.mapMayachainSwapError(error)
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
        vultTierDiscount: Int,
        slippageBps: Int?
    ) async throws -> SwapQuote {
        let rawAmount = fromCoin.raw(for: amount)
        let response = try await service.fetchQuotes(
            chain: String(chain),
            source: fromCoin.contractAddress,
            destination: toCoin.contractAddress,
            amount: String(rawAmount),
            from: fromCoin.address,
            isAffiliate: isAffiliate,
            vultTierDiscount: vultTierDiscount,
            slippageBps: slippageBps
        )
        return .oneinch(response.quote, fee: response.fee)
    }

    func fetchKyberSwapQuote(
        service: KyberSwapService,
        chain: String,
        amount: Decimal,
        fromCoin: Coin,
        toCoin: Coin,
        vultTierDiscount: Int,
        slippageBps: Int?
    ) async throws -> SwapQuote {
        let affiliateBps = vultTierDiscount >= 50 ? 0 : 50 - vultTierDiscount
        let rawAmount = fromCoin.raw(for: amount)
        let (quote, fee) = try await service.fetchQuotes(
            chain: chain,
            source: fromCoin.isNativeToken ? "" : fromCoin.contractAddress,
            destination: toCoin.isNativeToken ? "" : toCoin.contractAddress,
            amount: String(rawAmount),
            from: fromCoin.address,
            affiliateBps: affiliateBps,
            slippageBps: slippageBps
        )
        return .kyberswap(quote, fee: fee)
    }

    func fetchLiFiQuote(
        service: LiFiService,
        amount: Decimal,
        fromCoin: Coin,
        toCoin: Coin,
        vultTierDiscount: Int,
        slippageBps: Int?
    ) async throws -> SwapQuote {
        let fromAmount = fromCoin.raw(for: amount)
        let response = try await service.fetchQuotes(
            fromCoin: fromCoin,
            toCoin: toCoin,
            fromAmount: fromAmount,
            vultTierDiscount: vultTierDiscount,
            slippageBps: slippageBps
        )
        return .lifi(response.quote, fee: response.fee, integratorFee: response.integratorFee)
    }

    func fetchSwapKitQuote(
        service: SwapKitService,
        amount: Decimal,
        fromCoin: Coin,
        toCoin: Coin,
        vultTierDiscount: Int,
        slippageBps: Int?
    ) async throws -> SwapQuote {
        // Provider-cache gate — refuse to call `/v3/quote` for a chain SwapKit
        // doesn't enable. Fails open if the cache can't be loaded so we don't
        // silently disable the aggregator on a bad network day.
        let fromEnabled = await service.isChainEnabled(fromCoin.chain)
        let toEnabled = await service.isChainEnabled(toCoin.chain)
        guard fromEnabled, toEnabled else {
            throw SwapKitError.providerNotEnabled
        }
        // Mirror Kyber's `vultTierDiscount >= 50 ? 0 : 50 - vultTierDiscount`
        // shape via `max(0, ...)`, plus a defensive upper clamp at the
        // documented SwapKit ceiling (10% = 1000 bps). The `min` is
        // unreachable today because `vultTierDiscount` is bounded
        // server-side, but the API allows up to 1000 and the clamp guards
        // against any future loosening.
        let affiliateBps = max(0, min(1000, 50 - vultTierDiscount))
        // SwapKit takes slippage as a percent (Double). `Auto` (nil) omits it so
        // NEAR Intents can negotiate its own per-route slippage; a custom value
        // converts bps → percent (e.g. 50 bps → 0.5).
        let slippagePercent = slippageBps.map { Double($0) / 100 }
        guard let route = try await service.fetchBestRoute(
            fromCoin: fromCoin,
            toCoin: toCoin,
            amount: amount,
            slippagePercent: slippagePercent,
            affiliateFeeBps: affiliateBps
        ) else {
            throw SwapKitError.routeFiltered
        }
        let response = try await service.buildSwapTx(
            routeId: route.routeId,
            sourceAddress: fromCoin.address,
            destinationAddress: toCoin.address
        )
        return .swapkit(
            response,
            fee: service.inboundFee(from: response, fromCoin: fromCoin),
            subProvider: response.subProvider
        )
    }
}

// MARK: - Upstream error mapping

extension SwapService {
    /// Substrings THORChain/MAYAChain emit when a chain or asset is paused
    /// upstream (e.g. a protocol-wide trading halt after an incident). This is
    /// a *temporary* condition the user can retry, distinct from a permanently
    /// unsupported pair, so it gets its own user-facing message rather than the
    /// generic "route not available" or a leaked raw upstream string.
    private static let tradingHaltedMarkers = ["trading is halted", "trading halted"]

    private static func isTradingHalted(_ message: String) -> Bool {
        tradingHaltedMarkers.contains { message.localizedCaseInsensitiveContains($0) }
    }

    /// Translate a decoded THORChain quote error into the user-facing `SwapError`.
    /// A trading halt is detected on any code so a paused chain surfaces as a
    /// retryable message instead of `routeUnavailable`; otherwise the existing
    /// code-3 classification (fees / unsupported pair / raw server message) and
    /// the non-code-3 `routeUnavailable` fallback are preserved.
    static func mapThorchainSwapError(_ error: ThorchainSwapError) -> SwapError {
        if isTradingHalted(error.message) {
            return .tradingHalted
        }
        if error.code == 3 {
            if error.message.contains("not enough asset to pay for fees") {
                return .swapAmountTooSmall
            } else if error.message.localizedCaseInsensitiveContains("invalid symbol") ||
                error.message.localizedCaseInsensitiveContains("bad to asset") ||
                error.message.localizedCaseInsensitiveContains("bad from asset") ||
                error.message.localizedCaseInsensitiveContains("pool does not exist") {
                // This typically means no liquidity pool exists for this token pair
                return .noLiquidityPool
            } else {
                return .serverError(message: error.message)
            }
        }
        return .routeUnavailable
    }

    /// Translate a decoded MAYAChain quote error into the user-facing `SwapError`.
    /// A trading halt surfaces as the retryable message; any other error keeps
    /// the previous behaviour of relaying the raw upstream string.
    static func mapMayachainSwapError(_ error: MayachainSwapError) -> SwapError {
        if isTradingHalted(error.error) {
            return .tradingHalted
        }
        return .serverError(message: error.error)
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
        case .mayachain, .oneinch, .kyberswap, .lifi, .swapkit:
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
        vultTierDiscount: Int,
        toleranceBps: Int = SwapService.defaultThorchainToleranceBps
    ) async -> ThorchainSwapQuote {
        guard Self.supportsStreamingFallback(provider) else {
            return rapid
        }

        let slippageBps = Self.rapidSlippageBps(fromQuote: rapid) ?? 0
        let threshold = Self.streamingSlippageThresholdBps

        guard slippageBps > threshold else {
            logger.info("[anti-rekt] \(fromAsset, privacy: .public)→\(toAsset, privacy: .public) slippage=\(slippageBps, privacy: .public)bps ≤ \(threshold, privacy: .public)bps → RAPID out=\(rapid.expectedAmountOut, privacy: .public)")
            return rapid
        }

        // `max_streaming_quantity` is typically absent on rapid (interval=0) quotes,
        // so we pass 0 — THORChain's `streaming_quantity=0` means "protocol decides
        // optimal" and the chosen quantity is baked into the returned memo.
        let streamingQuantity = rapid.maxStreamingQuantity ?? 0

        do {
            let streaming = try await service.fetchSwapQuotes(
                address: address,
                fromAsset: fromAsset,
                toAsset: toAsset,
                amount: amount,
                interval: 1,
                streamingQuantity: streamingQuantity,
                toleranceBps: toleranceBps,
                referredCode: referredCode,
                vultTierDiscount: vultTierDiscount
            )
            let chosen = Self.selectBetterQuote(rapid: rapid, streaming: streaming)
            let pickedStreaming = chosen.expectedAmountOut == streaming.expectedAmountOut &&
                chosen.expectedAmountOut != rapid.expectedAmountOut
            logger.info("[anti-rekt] \(fromAsset, privacy: .public)→\(toAsset, privacy: .public) slippage=\(slippageBps, privacy: .public)bps > \(threshold, privacy: .public)bps, rapid=\(rapid.expectedAmountOut, privacy: .public), streaming=\(streaming.expectedAmountOut, privacy: .public) → \(pickedStreaming ? "STREAMING" : "RAPID", privacy: .public)")
            return chosen
        } catch {
            logger.warning("[anti-rekt] \(fromAsset, privacy: .public)→\(toAsset, privacy: .public) streaming fetch failed → RAPID: \(error.localizedDescription, privacy: .public)")
            return rapid
        }
    }
}
