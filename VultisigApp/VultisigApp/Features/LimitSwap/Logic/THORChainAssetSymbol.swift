//
//  THORChainAssetSymbol.swift
//  VultisigApp
//

import Foundation

/// Build a THORChain memo asset string for a given chain + ticker (+ token contract).
///
/// - Native: `<CHAIN>.<TICKER>` (e.g. `BTC.BTC`, `ETH.ETH`, `THOR.RUNE`).
/// - Token: `<CHAIN>.<TICKER>-<CONTRACT_SUFFIX>`, where `CONTRACT_SUFFIX` is
///   the last 6 characters of the contract address, uppercased — matching the
///   convention used by the market-swap proto path
///   (`THORChainSwapPayload.swapAsset(for:source:false)`).
///
/// Returns `nil` for chains not currently routable through THORChain.
func thorchainMemoAsset(
    chain: Chain,
    ticker: String,
    contractAddress: String,
    isNativeToken: Bool
) -> String? {
    guard let prefix = thorchainChainPrefix(for: chain) else {
        return nil
    }
    // Reject whitespace-only / empty tickers so the memo never gains a
    // malformed asset segment that fails downstream at memo/broadcast time.
    let normalizedTicker = ticker.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedTicker.isEmpty else { return nil }

    if isNativeToken {
        return "\(prefix).\(normalizedTicker)"
    }
    let normalized = contractAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    if prefix == "THOR" {
        // A THOR-chain non-native asset is encoded exactly like `Coin.swapAsset`'s
        // THOR branch — it NEVER takes the EVM last-6-of-contract suffix form.
        //
        // SECURED assets carry their full on-chain denom (`<l1>-<symbol>-<contract>`,
        // e.g. `eth-usdc-0xa0b…`) as the memo asset verbatim — the exact string
        // `Coin.swapAsset` emits for them. Detected the same way as
        // `THORChainHelper.isSecuredAsset`: a non-native THOR coin whose denom
        // contains `-` and isn't an `x/`-prefixed synth. Encoding one as a normal
        // token would target the wrong pool.
        if !normalized.hasPrefix("x/"), normalized.contains("-") {
            return normalized
        }
        // Every other THOR-native L1 token (e.g. TCY → `THOR.TCY`, RUJI →
        // `THOR.RUJI`) uses the bare `THOR.<TICKER>` form, matching
        // `Coin.swapAsset`'s non-secured THOR branch. TCY's `CoinMeta`
        // (contractAddress `"tcy"`, non-native) previously fell through the 6-char
        // suffix guard below and returned `nil`, so RUNE→TCY was a dead tap.
        return "\(prefix).\(normalizedTicker)"
    }
    // Non-THOR token form: `<CHAIN>.<TICKER>-<SUFFIX>` where SUFFIX is the last 6
    // chars of the contract address. Reject too-short or whitespace-only contracts
    // so the memo never gains a trailing `-` (or worse, a malformed suffix).
    guard normalized.count >= 6 else { return nil }
    let suffix = normalized.suffix(6).uppercased()
    return "\(prefix).\(normalizedTicker)-\(suffix)"
}

/// Convenience overload over `Coin`.
func thorchainMemoAsset(for coin: Coin) -> String? {
    thorchainMemoAsset(
        chain: coin.chain,
        ticker: coin.ticker,
        contractAddress: coin.contractAddress,
        isNativeToken: coin.isNativeToken
    )
}

/// Returns the THORChain memo prefix for a given chain (e.g. `BTC`, `ETH`,
/// `THOR`) — i.e. the chain identifier THORChain uses in inbound vault
/// listings and asset shorthand. Returns `nil` for chains the limit-swap
/// memo builder doesn't currently know how to encode.
func thorchainChainPrefix(for chain: Chain) -> String? {
    switch chain {
    case .thorChain, .thorChainChainnet, .thorChainStagenet:
        return "THOR"
    case .ethereum:
        return "ETH"
    case .avalanche:
        return "AVAX"
    case .bscChain:
        return "BSC"
    case .bitcoin:
        return "BTC"
    case .bitcoinCash:
        return "BCH"
    case .litecoin:
        return "LTC"
    case .dogecoin:
        return "DOGE"
    case .gaiaChain:
        return "GAIA"
    default:
        return nil
    }
}

/// Compute the set of chains routable through THORChain for the limit-swap
/// picker, from a live `inbound_addresses` list. Always includes `.thorChain`
/// (RUNE deposits settle via `MsgDeposit`, no inbound vault) plus every
/// non-halted / non-paused inbound whose chain symbol we can encode. Falls back
/// to the static prefix-table set when the inbound fetch returned nothing
/// useful, so the picker is never artificially empty rather than silently
/// allowing every chain.
///
/// Pure — the fetch is the caller's concern — so the halt-filtering + fallback
/// logic is unit-testable without hitting `ThorchainService.shared`.
func computeSupportedChains(from inbounds: [InboundAddress]) -> Set<Chain> {
    var chains: Set<Chain> = [.thorChain]
    for entry in inbounds {
        // Missing pause flags read as "not paused" — same convention as
        // `SwapHaltGate.isHalted(chain:in:)` on the market path.
        guard !entry.halted,
              !(entry.global_trading_paused ?? false),
              !(entry.chain_trading_paused ?? false) else { continue }
        if let chain = chainFromThorchainSymbol(entry.chain) {
            chains.insert(chain)
        }
    }
    if chains.count <= 1 {
        // Inbound fetch didn't return useful data — fall back to the static
        // routable set so the picker isn't artificially empty.
        return Set(Chain.allCases.filter { isThorchainRoutable(chain: $0) })
    }
    return chains
}

/// Whether a given chain is THORChain-routable per our static prefix table.
/// Used by the limit-swap picker to filter out chains the memo builder
/// can't encode (so the user can't pick e.g. SOL and hit a silent failure
/// when the memo build returns `nil`).
func isThorchainRoutable(chain: Chain) -> Bool {
    thorchainChainPrefix(for: chain) != nil
}

/// Reverse-lookup: given a THORChain chain string (`"BTC"`, `"ETH"`, …),
/// return our `Chain` enum case. Falls back to `nil` if the symbol isn't
/// in the prefix table — typically a chain THORChain has added that we
/// haven't coded a prefix for yet.
///
/// `"THOR"` matches three `Chain` cases (mainnet, chainnet, stagenet) so
/// the iteration alone would resolve based on enum order. Pin to canonical
/// mainnet (`.thorChain`) explicitly — Stagenet and Chainnet are dev
/// targets that wouldn't show up via a public `inbound_addresses` fetch
/// in production anyway.
func chainFromThorchainSymbol(_ symbol: String) -> Chain? {
    let upper = symbol
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .uppercased()
    guard !upper.isEmpty else { return nil }
    if upper == "THOR" { return .thorChain }
    return Chain.allCases.first { thorchainChainPrefix(for: $0) == upper }
}
