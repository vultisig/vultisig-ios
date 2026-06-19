//
//  SwapKitService.swift
//  VultisigApp
//
//  Two-step orchestrator for the SwapKit V3 surface: `/v3/quote` filters
//  THORChain/Maya and multi-hop routes client-side, then `/v3/swap` is called
//  once per chosen route to fetch the unsigned tx. Mirrors the existing
//  OneInch / Kyber / LiFi services in spirit.
//

import BigInt
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "swapkit-service")

struct SwapKitService {
    static let shared = SwapKitService()

    private let httpClient: HTTPClientProtocol
    private let providerCache: SwapKitProviderCache

    init(
        httpClient: HTTPClientProtocol = HTTPClient(),
        providerCache: SwapKitProviderCache = .shared
    ) {
        self.httpClient = httpClient
        self.providerCache = providerCache
    }

    /// Fetch all candidate routes for a (from, to) pair, drop the ones we
    /// can't sign (THORChain / Maya — already routed directly), drop multi-hop
    /// (single-hop only per design §3), and return the best one ranked by
    /// `expectedBuyAmount`. Returns `nil` instead of throwing when SwapKit is
    /// disabled (no API key, no enabled provider on the source chain) so the
    /// orchestrator can keep ranking other providers.
    func fetchBestRoute(
        fromCoin: Coin,
        toCoin: Coin,
        amount: Decimal,
        slippagePercent: Double? = nil,
        affiliateFeeBps: Int
    ) async throws -> SwapKitRoute? {
        // Opt-in feature flag (Settings → Advanced → "SwapKit"). When the
        // flag is off, short-circuit even if `Coin+Swaps.swapProviders`
        // already filtered `.swapkit` out — defense in depth so a future
        // call site that bypasses the provider list can't accidentally
        // light SwapKit up. The Vultisig proxy
        // (`api.vultisig.com/swapkit/`) attaches the partner API key
        // server-side; this flag exists to control client-side visibility
        // during smoke testing.
        guard SwapKitConfig.isFeatureEnabled else {
            logger.info("[swapkit] feature flag disabled — skipping fetch")
            return nil
        }

        // `sellAmount` must be a decimal-with-dot string (e.g. "0.0086"),
        // NOT raw base units. Per the SwapKit API contract:
        //   "Amount in basic units (decimals separated with a dot)"
        // Sending raw wei ("8600000000000000") causes SwapKit to interpret
        // the amount as 8.6 quadrillion BNB — far above any provider's
        // liquidity — and the quote returns `noRoutesFound`.
        //
        // Omit `slippage` from the request when the caller doesn't override.
        // Empirically, sending any explicit slippage value to NEAR Intents
        // for same-chain BSC pairs returns `noRoutesFound` — NEAR negotiates
        // its own per-route slippage based on the cross-chain settlement
        // model and a hard client-side cap (even 0.5%) is incompatible.
        // Letting SwapKit pick the per-provider default works for every pair
        // we've spike-tested. Override only when surfacing a user-tuned
        // slippage tolerance through the UI in a later phase.
        let request = SwapKitQuoteRequest(
            sellAsset: assetIdentifier(for: fromCoin),
            buyAsset: assetIdentifier(for: toCoin),
            sellAmount: Self.formatSellAmount(amount),
            sourceAddress: fromCoin.address.isEmpty ? nil : fromCoin.address,
            destinationAddress: toCoin.address.isEmpty ? nil : toCoin.address,
            slippage: slippagePercent,
            providers: nil,
            affiliateFee: affiliateFeeBps
        )

        do {
            let response = try await httpClient.request(
                SwapKitAPI.quote(request),
                responseType: SwapKitQuoteResponse.self
            )
            let filtered = Self.filterRoutes(response.data.routes)
            guard let best = Self.bestRoute(in: filtered) else {
                return nil
            }
            return best
        } catch HTTPError.statusCode(_, let data) {
            if let error = SwapKitError.from(httpData: data) {
                // SwapKit collapses "amount below provider minimum" and
                // "pair not supported" into a single byte-identical 404
                // `noRoutesFound` envelope. Cross-check the cached
                // `/v3/providers` snapshot: if a non-filtered provider
                // enables both chains, the pair IS structurally supported
                // and the failure must be amount-related — re-classify so
                // the view layer can show "Amount Too Small" instead of
                // the misleading "No routes available for this pair".
                if case .noRoutesFound = error,
                   await providerCache.isPairSupported(
                       fromChain: fromCoin.chain,
                       toChain: toCoin.chain
                   ) {
                    throw SwapKitError.amountBelowProviderMinimum
                }
                throw error
            }
            throw SwapKitError.generic(message: "SwapKit /v3/quote request failed")
        }
    }

    /// Two-call companion to `fetchBestRoute`. Called after a route is chosen
    /// (typically immediately after ranking) to fetch the unsigned tx
    /// payload. Surfaces SwapKit's documented error codes verbatim.
    func buildSwapTx(
        routeId: String,
        sourceAddress: String,
        destinationAddress: String,
        overrideSlippage: Bool = false
    ) async throws -> SwapKitSwapResponse {
        let request = SwapKitSwapRequest(
            routeId: routeId,
            sourceAddress: sourceAddress,
            destinationAddress: destinationAddress,
            overrideSlippage: overrideSlippage ? true : nil
        )
        do {
            let response = try await httpClient.request(
                SwapKitAPI.swap(request),
                responseType: SwapKitSwapResponse.self
            )
            return response.data
        } catch HTTPError.statusCode(_, let data) {
            if let error = SwapKitError.from(httpData: data) {
                throw error
            }
            throw SwapKitError.generic(message: "SwapKit /v3/swap request failed")
        }
    }

    /// Whether SwapKit should be offered as a provider for `chain` based on
    /// the cached `/v3/providers` snapshot. Falls back to "yes" when the cache
    /// can't be loaded — `/v3/quote` will surface a useful error if the chain
    /// is genuinely unsupported.
    func isChainEnabled(_ chain: Chain) async -> Bool {
        await providerCache.isEnabled(chain: chain)
    }

    // MARK: - Filtering (exposed for tests)

    static func filterRoutes(_ routes: [SwapKitRoute]) -> [SwapKitRoute] {
        routes.filter { route in
            // Drop multi-hop — single-hop only per design §3.
            guard route.providers.count == 1 else { return false }
            // Drop THORChain / Maya — Vultisig routes those directly.
            let providers = Set(route.providers.map { $0.uppercased() })
            return providers.isDisjoint(with: SwapKitConfig.filteredProviders)
        }
    }

    /// Rank by `expectedBuyAmount` (string-decimal). Higher wins. Stable on
    /// ties — first non-nil decimal wins to keep tests deterministic.
    static func bestRoute(in routes: [SwapKitRoute]) -> SwapKitRoute? {
        let ranked = routes.compactMap { route -> (SwapKitRoute, Decimal)? in
            guard let amount = Decimal(string: route.expectedBuyAmount) else { return nil }
            return (route, amount)
        }
        return ranked.max(by: { $0.1 < $1.1 })?.0
    }

    /// Format an amount as a dot-separated decimal string suitable for
    /// `SwapKitQuoteRequest.sellAmount`. SwapKit interprets the value as the
    /// human-readable amount of the source asset (e.g. "0.0086" BNB), NOT
    /// raw base units. Uses POSIX formatting to avoid locale-introduced
    /// commas. Trims trailing zeros after the decimal point so "1.0000"
    /// becomes "1" — matches what the docs samples show and what the spike
    /// fixtures pinned.
    static func formatSellAmount(_ amount: Decimal) -> String {
        var value = amount
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 38, .plain)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 38
        formatter.minimumFractionDigits = 0
        return formatter.string(from: rounded as NSDecimalNumber) ?? "\(amount)"
    }
}

// MARK: - Asset identifiers

extension SwapKitService {
    /// Source-chain network fee from a SwapKit swap response, in the source
    /// chain's native-gas-coin raw units. Feeds the verify-screen Network Fee
    /// row, the Total Fee (fiat), and the gas-coin sufficiency check in
    /// `SwapCryptoLogic.balanceError`.
    ///
    /// EVM sources derive the fee from the realised `tx.gas × tx.gasPrice`
    /// rather than the wire `inbound` `fees[]` entry. The `inbound` amount is a
    /// per-provider estimate: ONEINCH reports a plausible gas figure there, but
    /// FLASHNET-on-EVM returns a near-zero placeholder (~hundreds of wei) that
    /// renders as garbage like `0.00000000000000013 ETH` and a `$0.00` total.
    /// `gas × gasPrice` is the value the keysign path actually commits to
    /// (`SwapPayloadBuilder.buildEVMQuoteFromSwapKit`), so the displayed fee
    /// matches what the user is charged for every EVM sub-provider — the same
    /// convention KyberSwap / 1inch / LI.FI use for their own `fee` BigInt.
    ///
    /// Non-EVM sources keep the `inbound`-decimal path: the BTC PSBT, Solana,
    /// and TRON fixtures all report the real native miner/network fee there as
    /// a decimal native amount (e.g. "0.000005" SOL).
    func inboundFee(from response: SwapKitSwapResponse, fromCoin: Coin) -> BigInt? {
        if case let .evm(tx) = response.tx {
            return evmNetworkFee(from: tx, isNativeSource: fromCoin.isNativeToken)
        }
        return inboundFeeFromWire(response: response, fromCoin: fromCoin)
    }

    /// EVM network fee = `gasPrice × gas` in wei, parsing the hex `SwapKitEvmTx`
    /// fields. SwapKit's reported `tx.gas` is respected whenever it's present —
    /// the same convention 1inch / Kyber / LI.FI use for their own `fee`. Only a
    /// route that omits the limit (`gas == 0`) falls back to a default so the row
    /// shows a representative fee instead of zero: native sources to the swap gas
    /// unit, ERC-20 sources (which need a token approval) to the token-transfer
    /// unit.
    func evmNetworkFee(from tx: SwapKitEvmTx, isNativeSource: Bool) -> BigInt? {
        let gasPrice = BigInt(tx.gasPrice.stripHexPrefix(), radix: 16) ?? .zero
        let parsedGas = BigInt(tx.gas.stripHexPrefix(), radix: 16) ?? .zero
        let fallbackGas = isNativeSource
            ? BigInt(EVMHelper.defaultETHSwapGasUnit)
            : BigInt(EVMHelper.defaultERC20TransferGasUnit)
        let gas = parsedGas == .zero ? fallbackGas : parsedGas
        let fee = gasPrice * gas
        return fee == .zero ? nil : fee
    }

    private func inboundFeeFromWire(response: SwapKitSwapResponse, fromCoin: Coin) -> BigInt? {
        let prefix = chainPrefix(for: fromCoin.chain, fallback: fromCoin.ticker)
        guard
            let inbound = response.fees.first(where: { $0.type == "inbound" && $0.chain == prefix }),
            let amount = Decimal(string: inbound.amount)
        else {
            return nil
        }
        // The inbound fee is denominated in the source chain's NATIVE gas coin (e.g. "BTC.BTC",
        // "SOL.SOL"), never the sell token. Scaling by `fromCoin.decimals` under-counts the fee
        // for an SPL/UTXO token source (e.g. a 6-dp token vs the chain's native decimals), which
        // reads as dust on the Network Fee row and weakens the gas-coin balance check. Scale by
        // the native coin's decimals — identical to `fromCoin.decimals` on a native-source route.
        var scaled = amount * pow(Decimal(10), nativeDecimals(for: fromCoin))
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .up)
        let raw = BigInt(rounded.description) ?? .zero
        return raw == .zero ? nil : raw
    }
}

private extension SwapKitService {
    /// SwapKit asset identifier format: `Chain.Ticker` for native tokens,
    /// `Chain.Ticker-Contract` for tokens with an on-chain contract address.
    /// See `api-contract.md` for the canonical chain prefix table.
    func assetIdentifier(for coin: Coin) -> String {
        let prefix = chainPrefix(for: coin.chain, fallback: coin.ticker)
        if coin.isNativeToken || coin.contractAddress.isEmpty {
            return "\(prefix).\(coin.ticker)"
        }
        return "\(prefix).\(coin.ticker)-\(coin.contractAddress)"
    }

    func chainPrefix(for chain: Chain, fallback: String) -> String {
        // Canonical prefixes verified empirically against
        // `/v3/tokens?provider=NEAR` — SwapKit uses chain-specific tickers
        // for EVM L2s and BSC, not the gas-token tickers Vultisig stores in
        // `coin.ticker`. Mismatches surface as `helpers_invalid_asset_identifier`
        // 500s from the proxy at quote time.
        switch chain {
        case .ethereum: return "ETH"
        case .base: return "BASE"
        case .optimism: return "OP"
        case .arbitrum: return "ARB"
        case .avalanche: return "AVAX"
        case .bscChain: return "BSC"
        case .polygon, .polygonV2: return "POL"
        case .solana: return "SOL"
        case .bitcoin: return "BTC"
        case .bitcoinCash: return "BCH"
        case .litecoin: return "LTC"
        case .dogecoin: return "DOGE"
        case .tron: return "TRON"
        case .ton: return "TON"
        case .cardano: return "ADA"
        case .sui: return "SUI"
        case .ripple: return "XRP"
        case .dash: return "DASH"
        case .zcash: return "ZEC"
        case .gaiaChain: return "ATOM"
        case .kujira: return "KUJI"
        case .thorChain, .thorChainChainnet, .thorChainStagenet: return "THOR"
        case .mayaChain: return "MAYA"
        default: return fallback
        }
    }

    /// Decimals to scale the inbound fee by. The fee is always denominated in the source chain's
    /// native gas coin, so a native-source coin already carries the right decimals; for an ERC-20 /
    /// SPL token source we look up the chain's native coin (whose decimals differ from the token's)
    /// rather than hardcoding a per-chain table. Falls back to the source coin's own decimals if the
    /// native coin isn't in the curated store.
    func nativeDecimals(for coin: Coin) -> Int {
        if coin.isNativeToken {
            return coin.decimals
        }
        let nativeCoin = TokensStore.TokenSelectionAssets.first {
            $0.chain == coin.chain && $0.isNativeToken
        }
        return nativeCoin?.decimals ?? coin.decimals
    }
}
