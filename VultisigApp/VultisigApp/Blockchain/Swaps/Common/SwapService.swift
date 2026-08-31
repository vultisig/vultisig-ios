//
//  SwapService.swift
//  VoltixApp
//
//  Created by Artur Guseinov on 07.05.2024.
//

import Foundation
import OSLog

private let logger = Log.swap.service

struct SwapProviderQuoteResult {
    let provider: SwapProvider
    let result: Result<SwapQuote, Error>

    var quote: SwapQuote? { try? result.get() }

    var error: Error? {
        guard case .failure(let error) = result else { return nil }
        return error
    }
}

struct SwapService {
    static let shared = SwapService()

    typealias QuoteFetcherOverride = @Sendable (SwapProvider) async throws -> SwapQuote

    private let quoteFetcherOverride: QuoteFetcherOverride?

    init(quoteFetcherOverride: QuoteFetcherOverride? = nil) {
        self.quoteFetcherOverride = quoteFetcherOverride
    }

    /// Fall back from rapid to streaming THORChain swap when rapid slippage
    /// (`fees.total` share of output) exceeds this threshold. 100 bps = 1%.
    /// Streaming typically drops slippage from ~41 bps to ~9 bps on trades
    /// it covers; a 1% cutoff captures mid-size cross-chain swaps that
    /// otherwise route via rapid despite being good streaming candidates.
    /// Mirrored in `vultisig-sdk` (`THORCHAIN_STREAMING_SLIPPAGE_THRESHOLD_BPS`)
    /// and `vultisig-android` (`STREAMING_SLIPPAGE_THRESHOLD_BPS`).
    static let streamingSlippageThresholdBps = 100

    /// `Auto` slippage default, sent as `liquidity_tolerance_bps`. 100 bps = 1%.
    ///
    /// The node bakes this into the returned memo as a `LIM` floor of exactly
    /// `floor(expected_amount_out × (10_000 − bps) / 10_000)`, so an `Auto` swap
    /// gets on-chain protection instead of settling at any price.
    ///
    /// This is *not* the same knob as `tolerance_bps` — the node rejects a
    /// request carrying both. `tolerance_bps` is gated against the single-swap
    /// emit while anchored to the feeless price, so it refuses any swap with
    /// real price impact; `liquidity_tolerance_bps` is immune to price impact
    /// and yields a clean 1% floor at every size on both THORChain and Maya.
    ///
    /// A user-set slippage overrides this, and a user-set 0 still omits the
    /// parameter entirely (no floor).
    static let defaultLiquidityToleranceBps = 100

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
        // THORChain / MayaChain are offered at the chain level, so provider
        // overlap here decides which native + aggregator routes are attempted;
        // the live quote prunes a native route with no real pool.
        let resolvedProviders = SwapCoinsResolver.resolveAllProviders(
            fromCoin: fromCoin,
            toCoin: toCoin
        )

        guard !resolvedProviders.isEmpty else {
            throw SwapError.routeUnavailable
        }

        // When an external recipient is set, only routes that actually deliver to
        // that address (THORChain/Maya, via the memo destination) may be ranked.
        // Aggregators build the swap tx with the user's own address and silently
        // ignore the recipient, so letting `selectBestQuote` pick one would send
        // funds to self while the verify screen shows the external recipient
        // (silent fund-misdirection). Filtering the candidate pool up front keeps
        // the no-recipient path byte-identical (no recipient → no filtering).
        let providers = Self.providersHonoringRecipient(resolvedProviders, recipientAddress: recipientAddress)

        guard !providers.isEmpty else {
            // An external recipient was requested but no recipient-honouring route
            // exists for this pair — surface a clear error instead of silently
            // routing to self.
            throw SwapError.recipientRouteUnavailable
        }

        func fetchResults(for attemptedProviders: [SwapProvider]) async -> [SwapProviderQuoteResult] {
            await withTaskGroup(of: SwapProviderQuoteResult.self) { group in
                for provider in attemptedProviders {
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
                            return SwapProviderQuoteResult(provider: provider, result: .success(quote))
                        } catch {
                            return SwapProviderQuoteResult(provider: provider, result: .failure(error))
                        }
                    }
                }

                var collected: [SwapProviderQuoteResult] = []
                for await result in group {
                    collected.append(result)
                }
                return collected
            }
        }

        var results = await fetchResults(for: providers)
        if results.allSatisfy({ $0.quote == nil }) {
            let retryProviders = Self.transientAggregatorRetryProviders(from: results)
            if !retryProviders.isEmpty {
                let retried = await fetchResults(for: retryProviders)
                results.removeAll { retryProviders.contains($0.provider) }
                results.append(contentsOf: retried)
            }
        }

        let quotes = results.compactMap(\.quote)
        if let best = Self.selectBestQuote(quotes: quotes, toCoin: toCoin) {
            let ranked = Self.rankedQuotes(quotes: quotes, toCoin: toCoin)
            // Preserve the `best ∈ ranked` contract: if nothing is rankable (no
            // comparable net amounts) but a best still exists, surface it.
            return SwapQuotes(best: best, ranked: ranked.isEmpty ? [best] : ranked)
        }

        throw Self.surfacedProviderQuoteError(from: results) ?? SwapError.routeUnavailable
    }

    static func transientAggregatorRetryProviders(
        from results: [SwapProviderQuoteResult]
    ) -> [SwapProvider] {
        let nativeProviderHalted = results.contains { result in
            result.provider.isNativeProtocol && isTradingHalted(result.error)
        }
        guard nativeProviderHalted else { return [] }

        return results.compactMap { result in
            guard result.provider.isAggregator,
                  let error = result.error,
                  isTransientAggregatorError(error)
            else { return nil }
            return result.provider
        }
    }

    static func surfacedProviderQuoteError(from results: [SwapProviderQuoteResult]) -> Error? {
        let failures = results.compactMap { result -> (provider: SwapProvider, error: Error)? in
            guard let error = result.error else { return nil }
            return (result.provider, error)
        }

        let hasNativeHalt = failures.contains {
            $0.provider.isNativeProtocol && isTradingHalted($0.error)
        }
        guard hasNativeHalt else {
            return surfacedQuoteError(from: failures.map(\.error))
        }

        let alternatives = failures.filter {
            !($0.provider.isNativeProtocol && isTradingHalted($0.error))
        }
        guard !alternatives.isEmpty else { return SwapError.tradingHalted }
        guard !alternatives.allSatisfy({ isStructuralRouteError($0.error) }) else {
            return SwapError.tradingHalted
        }

        return surfacedQuoteError(from: alternatives.map(\.error))
    }

    private static func isTradingHalted(_ error: Error?) -> Bool {
        guard let swapError = error as? SwapError else { return false }
        return swapError == .tradingHalted
    }

    private static func isStructuralRouteError(_ error: Error) -> Bool {
        if let swapError = error as? SwapError {
            return swapError == .routeUnavailable || swapError == .noLiquidityPool
        }

        if let swapKitError = error as? SwapKitError {
            switch swapKitError {
            case .swapRouteNotFound, .noRoutesFound, .providerNotEnabled, .routeFiltered, .unsupportedTxType:
                return true
            default:
                return false
            }
        }

        if let liFiError = error as? LiFiSwapError {
            let message = liFiError.message.lowercased()
            return ["no route", "not found", "not supported", "unsupported"].contains {
                message.contains($0)
            }
        }

        return false
    }

    private static func isTransientAggregatorError(_ error: Error) -> Bool {
        if error is URLError { return true }

        if let httpError = error as? HTTPError {
            switch httpError {
            case .timeout, .networkError, .noData, .invalidResponse, .decodingFailed:
                return true
            case .statusCode(let code, _):
                return code >= 500
            case .invalidURL, .encodingFailed, .invalidSSLCertificate:
                return false
            }
        }

        if let swapError = error as? SwapError {
            if case .serverError = swapError { return true }
            return false
        }

        if let swapKitError = error as? SwapKitError {
            switch swapKitError {
            case .addressScreeningFailed, .unableToBuildTransaction, .generic:
                return true
            default:
                return false
            }
        }

        if error is LiFiSwapError { return !isStructuralRouteError(error) }

        if let kyberError = error as? KyberSwapError,
           case .apiError(let code, _, _) = kyberError {
            return code >= 500
        }

        if let jupiterError = error as? JupiterError {
            switch jupiterError {
            case .quoteFailed(let code), .swapFailed(let code):
                return code >= 500
            case .invalidQuote:
                return true
            case .feeAccountUnavailable, .feeAccountNotProvisioned:
                return false
            }
        }

        // LI.FI's undecodable 5xx path and 1inch's relay are private error
        // types, so their provider identity is the only retry-safe signal left.
        return true
    }

    /// Pick which provider error to surface once every eligible provider failed
    /// to produce a usable quote.
    ///
    /// SwapKit is an *optional* aggregator layered on top of the core routing
    /// providers (THORChain/Maya/1inch/KyberSwap/LI.FI). Its failures must never
    /// degrade the experience versus not having SwapKit at all. The motivating
    /// case: SwapKit's `/v3/quote` AML screening intermittently returns
    /// `addressScreeningFailed` ("Address screening failed — contact support")
    /// when its screening provider has an outage. The providers run in parallel
    /// and each failure is collected independently, so when that transient error
    /// wins the task-completion race it gets surfaced as the user-facing error —
    /// making a pair that routes fine elsewhere (e.g. ETH→GRT via KyberSwap) look
    /// permanently broken and telling the user to "contact support".
    ///
    /// So prefer any non-SwapKit error: those come from the core providers and
    /// describe the real routing outcome (no route, amount too small, etc.). Fall
    /// back to a SwapKit error only when SwapKit was the sole provider attempted
    /// (e.g. TON/Cardano/Sui pairs), where it's the only signal available.
    ///
    /// Within the chosen pool, `.serverError` sorts last. `errors` arrives in
    /// task-completion order, so `first` alone is a network race: a poolless
    /// THORChain↔EVM pair fails on THORChain and MAYAChain simultaneously, and
    /// whichever node answered first decided whether the user saw "No liquidity
    /// pool available for this token pair" or the losing node's raw body. Same
    /// failure, different sentence on every refresh.
    ///
    /// Only `.serverError` is demoted, not "everything that isn't a typed
    /// `SwapError`" — a Kyber/LI.FI/transport failure carries its own specific
    /// description and must keep its place, or a provider that merely answered
    /// slower could downgrade "Insufficient funds" to "No Route Available".
    static func surfacedQuoteError(from errors: [Error]) -> Error? {
        let coreProviderErrors = errors.filter { !($0 is SwapKitError) }
        let pool = coreProviderErrors.isEmpty ? errors : coreProviderErrors
        return pool.first(where: { !isUnclassifiedRelay($0) }) ?? pool.first
    }

    /// Whether an error is only a container for text an upstream provider sent
    /// and this app could not classify — as opposed to any error that carries a
    /// verdict of its own, typed or described.
    private static func isUnclassifiedRelay(_ error: Error) -> Bool {
        guard let swapError = error as? SwapError, case .serverError = swapError else {
            return false
        }
        return true
    }

    /// Restrict the candidate provider set so a quote can never be ranked/selected
    /// for a route that won't honour the external recipient. With no external
    /// recipient (`nil`/blank) the input set is returned unchanged — the
    /// no-recipient quote path stays byte-identical. With an external recipient
    /// set, only `honorsExternalRecipient` providers (THORChain/Maya) survive; the
    /// aggregators are dropped because they'd silently send the swap output to the
    /// user's own address.
    static func providersHonoringRecipient(
        _ providers: [SwapProvider],
        recipientAddress: String?
    ) -> [SwapProvider] {
        let hasExternalRecipient = recipientAddress?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false
        guard hasExternalRecipient else { return providers }
        return providers.filter { $0.honorsExternalRecipient }
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
    /// the higher-priority provider is preferred over a marginally larger raw output. 50bps.
    static let providerPreferenceBand: Decimal = 0.005

    /// Pick the best quote across providers. The ranking metric is net output in `toCoin`
    /// units (every provider in a candidate set swaps to the same `toCoin`, so the
    /// destination amount is directly comparable). On top of that metric a banded
    /// provider-preference layer applies: among quotes within `providerPreferenceBand` (50bps)
    /// of the best net output — economically equivalent on net output — a lower source-chain
    /// gas cost wins first (same-chain EVM aggregators only, where `sourceGasWei` is exposed in
    /// the same native-wei unit), then the highest-priority provider, then the higher net
    /// output. The lower-gas check only fires when BOTH compared quotes expose `sourceGasWei`,
    /// so a gas-unknown quote (THORChain/Maya/SwapKit cross-chain) never falsely wins it and
    /// instead falls through to provider preference. This keeps near-tie routes on the cheaper
    /// or more trusted route without ever trading away a materially better rate (anything
    /// outside the band loses on output).
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

        // Quotes within the band of the best net output are treated as tied on rate. Among
        // those, prefer (1) lower source-chain gas when BOTH quotes expose it in the same
        // native-wei unit (same-chain EVM aggregators) — a gas-unknown quote must not win this
        // check, so it falls through; then (2) the higher-priority (lower index) provider; then
        // (3) higher net output (defensive — a provider rarely appears twice).
        let floor = best.1 * (1 - providerPreferenceBand)
        let inBand = ranked.filter { $0.1 >= floor }
        let picked = inBand.min { lhs, rhs in
            if let lhsGas = lhs.0.sourceGasWei, let rhsGas = rhs.0.sourceGasWei, lhsGas != rhsGas {
                return lhsGas < rhsGas
            }
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
    /// (all networks) is most preferred, then Maya, SwapKit, KyberSwap, 1inch, Jupiter, LI.FI.
    /// Jupiter sits just above LI.FI so on-Solana token swaps prefer Jupiter (no aggregator
    /// markup) when its net output is within the band, while LI.FI still wins when materially
    /// better.
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
        case .jupiter:
            return 5
        case .lifi:
            return 6
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
        if let quoteFetcherOverride {
            return try await quoteFetcherOverride(provider)
        }

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
                slippageBps: slippageBps,
                recipientAddress: recipientAddress
            )
        case .jupiter:
            return try await fetchJupiterQuote(
                service: JupiterService.shared,
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

            // `Auto` (nil) takes the default 1% tolerance; a custom slippage
            // maps directly to `liquidity_tolerance_bps`, which the node bakes
            // into the returned memo's `LIM` floor.
            let liquidityToleranceBps = slippageBps ?? Self.defaultLiquidityToleranceBps

            // External recipient (when set) becomes the swap's `destination` — the
            // node encodes it into the returned memo, so the swapped funds land at
            // the external address instead of the user's own. Defaults to the
            // user's own destination address. For a THORChain secured-asset
            // `toCoin` the mint settles on THORChain, so the destination must be a
            // THORChain (`thor1…`) address — enforced here so a non-THORChain
            // destination surfaces a clear error instead of a collapsed quote.
            let destination = try Self.resolveThorchainDestination(
                toCoin: toCoin,
                recipientAddress: recipientAddress
            )

            let rapidQuote = try await service.fetchSwapQuotes(
                address: destination,
                fromAsset: fromCoin.swapAsset,
                toAsset: toCoin.swapAsset,
                amount: truncatedAmount.description,
                interval: provider.streamingInterval,
                liquidityToleranceBps: liquidityToleranceBps,
                referredCode: referredCode,
                vultTierDiscount: vultTierDiscount
            )

            guard let expected = Decimal(string: rapidQuote.expectedAmountOut), !expected.isZero else {
                throw SwapError.swapAmountTooSmall
            }

            if let belowMinimum = Self.belowRecommendedMinimumError(
                normalizedAmount: normalizedAmount,
                recommendedMinAmountIn: rapidQuote.recommendedMinAmountIn,
                fromCoin: fromCoin
            ) {
                throw belowMinimum
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
                liquidityToleranceBps: liquidityToleranceBps
            )

            return service.makeSwapQuote(quote)
        } catch let error as ThorchainSwapError {
            logger.error("THORChain swap error: code=\(error.code, privacy: .public), message=\(error.message, privacy: .public)")
            throw Self.mapThorchainSwapError(error)
        } catch let error as MayachainSwapError {
            logger.error("MAYAChain swap error: code=\(error.code ?? -1, privacy: .public), message=\(error.error, privacy: .public)")
            throw Self.mapMayachainSwapError(error)
        } catch let error as SwapError {
            throw error
        } catch {
            // Any error not classified above (timeout, TLS, decode, node 5xx)
            // is unknown here — surface the real error instead of a confident
            // "amount too small" money verdict the app cannot actually justify.
            logger.error("Cross-chain quote failed with unclassified error: \(error.localizedDescription, privacy: .public)")
            throw error
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
        slippageBps: Int?,
        recipientAddress: String?
    ) async throws -> SwapQuote {
        guard SwapKitCapability.canQuote(from: fromCoin.chain) else {
            throw SwapKitError.providerNotEnabled
        }
        // Provider-cache gate — refuse to call `/v3/quote` for a chain SwapKit
        // doesn't enable. Fails CLOSED on the no-snapshot edge (throws
        // `providerNotEnabled`) rather than offering routes that fail
        // downstream; once a snapshot exists, `SwapKitProviderCache` serves it
        // as last-good so a transient network blip doesn't disable SwapKit.
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
        // External recipient (when set) becomes SwapKit's `destinationAddress`
        // for both `/v3/quote` (AML screening + route discovery) and `/v3/swap`
        // (the build that pins where the bought asset is delivered). Defaults to
        // the user's own destination address. The echoed `destinationAddress` is
        // verified against the recipient before signing (`SwapRecipientVerifier`).
        let destination = recipientAddress ?? toCoin.address
        guard let route = try await service.fetchBestRoute(
            fromCoin: fromCoin,
            toCoin: toCoin,
            amount: amount,
            destinationAddress: destination,
            slippagePercent: slippagePercent,
            affiliateFeeBps: affiliateBps
        ) else {
            throw SwapKitError.routeFiltered
        }
        let response = try await service.buildSwapTx(
            routeId: route.routeId,
            sourceAddress: fromCoin.address,
            destinationAddress: destination
        )
        try SwapKitService.validateSigningCapability(
            response: response,
            fromChain: fromCoin.chain
        )
        return .swapkit(
            response,
            fee: service.inboundFee(from: response, fromCoin: fromCoin),
            subProvider: response.subProvider
        )
    }

    func fetchJupiterQuote(
        service: JupiterService,
        amount: Decimal,
        fromCoin: Coin,
        toCoin: Coin,
        vultTierDiscount: Int,
        slippageBps: Int?
    ) async throws -> SwapQuote {
        let fromAmount = fromCoin.raw(for: amount)
        let (quote, fee, platformFee, feeOnInput) = try await service.fetchQuote(
            fromCoin: fromCoin,
            toCoin: toCoin,
            fromAmount: fromAmount,
            vultTierDiscount: vultTierDiscount,
            slippageBps: slippageBps
        )
        return .jupiter(quote, fee: fee, platformFee: platformFee, feeOnInput: feeOnInput)
    }
}

// MARK: - Recommended-minimum guard

extension SwapService {
    /// The per-candidate "below the node's own recommended floor" verdict for a
    /// native THORChain/MAYAChain quote, or `nil` when the amount clears it.
    ///
    /// The comparison stays in node fixed-point units. The multiplier comes from
    /// the source coin's native scale (1e10 for CACAO), while off-chain assets
    /// use THORChain's 1e8 scale. The same multiplier converts the node's floor
    /// back to a user-facing amount.
    ///
    /// A present but malformed floor fails open. An omitted floor fails quote
    /// decoding earlier because `recommendedMinAmountIn` is required.
    static func belowRecommendedMinimumError(
        normalizedAmount: Decimal,
        recommendedMinAmountIn: String,
        fromCoin: Coin
    ) -> SwapError? {
        guard let minimum = Decimal(string: recommendedMinAmountIn),
              normalizedAmount < minimum else {
            return nil
        }
        let recommendedAmount = "\(minimum / fromCoin.thorswapMultiplier) \(fromCoin.ticker)"
        return .lessThenMinSwapAmount(amount: recommendedAmount)
    }
}

// MARK: - THORChain swap destination

extension SwapService {
    /// Resolve the `destination` for a native THORChain/MAYAChain swap quote.
    ///
    /// The existing contract is preserved: an explicit external recipient (when
    /// set) becomes the destination; otherwise it's the user's own receiving
    /// address for `toCoin`.
    ///
    /// The one addition is a guard for THORChain **secured assets**. A secured
    /// asset is minted *on THORChain* (quote memo `=:ETH-USDC:thor1…:0/1/0`), so
    /// its destination must be a THORChain (`thor1…`) address. For a
    /// `chain == .thorChain` `toCoin` that is exactly `toCoin.address` — derived
    /// from the vault key, independent of the secured denom in `contractAddress`.
    /// If that resolved destination is somehow not a THORChain address (e.g. an
    /// empty or L1 `0x…` value), THORNode rejects the quote with "swap
    /// destination address is not the same chain as the target asset"; we reject
    /// it up front with a clear, message-bearing error instead of letting it
    /// collapse into a generic `routeUnavailable`. Non-secured and external-
    /// recipient paths are unchanged.
    static func resolveThorchainDestination(toCoin: Coin, recipientAddress: String?) throws -> String {
        let destination = recipientAddress ?? toCoin.address

        if recipientAddress == nil,
           THORChainHelper.isSecuredAsset(coin: toCoin),
           !THORChainHelper.isValidThorchainAddress(destination, chain: toCoin.chain) {
            throw SwapError.securedAssetInvalidDestination(
                expectedPrefix: THORChainHelper.expectedAddressPrefix(for: toCoin.chain),
                destination: destination.nilIfEmpty ?? "empty"
            )
        }

        return destination
    }
}

// MARK: - Upstream error mapping

extension SwapService {
    /// Substrings THORChain/MAYAChain emit when a chain or asset is paused
    /// upstream (e.g. a protocol-wide trading halt after an incident). This is
    /// a *temporary* condition the user can retry, distinct from a permanently
    /// unsupported pair, so it gets its own user-facing message rather than the
    /// generic "route not available" or a leaked raw upstream string.
    private static let tradingHaltedMarkers = [
        "trading is halted",
        "trading halted",
        "trading paused",
        "_trading_paused",
        "is paused"
    ]

    private static func isTradingHalted(_ message: String) -> Bool {
        tradingHaltedMarkers.contains { message.localizedCaseInsensitiveContains($0) }
    }

    /// Substrings that name the missing asset itself rather than the pool.
    private static let unknownAssetMarkers = [
        "invalid symbol",
        "bad to asset",
        "bad from asset"
    ]

    /// Ways the two nodes spell "… does not exist".
    private static let missingVerbs = ["does not exist", "doesn't exist", "doesn\u{2019}t exist"]

    /// Whether a native quote-error body says "this pair has no pool".
    ///
    /// The two nodes word the identical verdict differently — THORChain returns
    /// `…fail to convert dest fee to src asset pool does not exist`, MAYAChain
    /// returns `failed to simulate swap: pool <ASSET> doesn't exist` — so
    /// matching only THORChain's phrasing left Maya's verdict unclassified and
    /// relayed its raw node text instead.
    ///
    /// Matched per clause, not per message. Both real bodies name the pool and
    /// the verb in the same clause; requiring that keeps a body that mentions a
    /// pool in one clause and something else missing in another from reading as
    /// a missing pool. THORNode uses the same verb for an unrelated failure —
    /// `bad destination address: unable to parse address: THORName doesn't exist: thor1…`
    /// — and reporting that as a missing pool would send the user off to pick a
    /// different asset when the fault is the address.
    private static func isMissingPool(_ message: String) -> Bool {
        if unknownAssetMarkers.contains(where: { message.localizedCaseInsensitiveContains($0) }) {
            return true
        }
        return message
            .lowercased()
            .split(whereSeparator: { $0 == ":" || $0 == ";" })
            .contains { clause in
                clause.contains("pool") && missingVerbs.contains { clause.contains($0) }
            }
    }

    /// Classify a native (THORChain/MAYAChain) quote-error body into a typed
    /// `SwapError`, shared by both branches so Maya stops leaking dust-minimum /
    /// missing-pool errors as a raw `.serverError`. Returns `nil` when the body
    /// matches none of the known classes; the caller then applies its own
    /// fallback (`.serverError`, which carries the upstream text for logs and
    /// renders as generic copy on screen).
    private static func classifyNativeQuoteError(_ message: String) -> SwapError? {
        if message.contains("not enough asset to pay for fees") ||
            message.localizedCaseInsensitiveContains("zero emit asset") {
            // "zero emit asset" means the input is below the dust/fee threshold —
            // the same class as "not enough asset to pay for fees", surfaced as
            // the retry-with-more message.
            return .swapAmountTooSmall
        }
        if isMissingPool(message) {
            // No liquidity pool exists for this token pair.
            return .noLiquidityPool
        }
        if message.localizedCaseInsensitiveContains("less than price limit") {
            // The node simulated the swap and its output landed under the `LIM`
            // floor derived from the slippage tolerance we sent. Raw, this reads
            // as "emit asset N less than price limit M" — meaningless to a user.
            // Surface it as the actionable slippage message instead.
            return .slippageToleranceTooTight
        }
        return nil
    }

    /// Translate a decoded THORChain quote error into the typed `SwapError`.
    /// A trading halt is detected on any code so a paused chain surfaces as a
    /// retryable message. Otherwise the known dust/fee/missing-pool classes are
    /// mapped to their typed errors and anything else is carried in
    /// `.serverError` — so a specific, actionable failure (e.g. code 2 "swap
    /// destination address is not the same chain as the target asset") stays
    /// diagnosable in the logs instead of collapsing into a generic
    /// `routeUnavailable`. The tooltip shows generic copy for `.serverError`
    /// rather than the node's own wording. Only a truly empty message falls back
    /// to `routeUnavailable`.
    static func mapThorchainSwapError(_ error: ThorchainSwapError) -> SwapError {
        if isTradingHalted(error.message) {
            return .tradingHalted
        }
        if let classified = classifyNativeQuoteError(error.message) {
            return classified
        }
        return error.message.isEmpty ? .routeUnavailable : .serverError(message: error.message)
    }

    /// Translate a decoded MAYAChain quote error into the typed `SwapError`.
    /// A trading halt surfaces as the retryable message; the shared dust-minimum
    /// / missing-pool classification (previously THORChain-only) applies here too,
    /// so those no longer leak as a raw `.serverError`. Anything unrecognised is
    /// carried in `.serverError`, which keeps the raw upstream string for the logs
    /// and renders as generic copy on screen.
    static func mapMayachainSwapError(_ error: MayachainSwapError) -> SwapError {
        if isTradingHalted(error.error) {
            return .tradingHalted
        }
        return classifyNativeQuoteError(error.error) ?? .serverError(message: error.error)
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
        case .mayachain, .oneinch, .kyberswap, .lifi, .swapkit, .jupiter:
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
        liquidityToleranceBps: Int = SwapService.defaultLiquidityToleranceBps
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
                liquidityToleranceBps: liquidityToleranceBps,
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
