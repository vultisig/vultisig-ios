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
    if isNativeToken {
        return "\(prefix).\(ticker)"
    } else {
        let suffix = contractAddress.suffix(6).uppercased()
        return "\(prefix).\(ticker)-\(suffix)"
    }
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
func chainFromThorchainSymbol(_ symbol: String) -> Chain? {
    let upper = symbol.uppercased()
    return Chain.allCases.first { thorchainChainPrefix(for: $0) == upper }
}
