//
//  NativePoolAsset.swift
//  VultisigApp
//
//  Normalized representation of a single THORChain / MayaChain swap pool,
//  parsed from a `/pools` response asset id (`CHAIN.TICKER-0XCONTRACT`). The
//  embedded contract is used only to disambiguate a same-ticker collision —
//  it is never a curated allowlist.
//

import Foundation

/// Which native protocol a pool snapshot belongs to.
enum NativeSwapProtocol {
    case thorchain
    case mayachain
}

/// A live native-protocol swap pool, normalized from a `/pools` response.
struct NativePoolAsset: Hashable {
    /// The L1 the pool's asset lives on, e.g. `.ethereum`.
    let poolChain: Chain
    /// Uppercased ticker, e.g. `"USDT"`.
    let ticker: String
    /// Lowercased `0x…` ERC-20 contract address; `nil` for L1 natives.
    let contract: String?
    /// `status == "Available"`.
    let isAvailable: Bool
    /// THORChain per-pool `trading_halted` flag; always `false` for Maya pools.
    let isTradingHalted: Bool
}

/// Per-protocol snapshot with its fetch time, mirroring `SwapKitProvidersSnapshot`.
struct NativePoolSnapshot {
    let pools: [NativePoolAsset]
    let fetchedAt: Date
}

extension NativePoolAsset {

    /// Maps a `/pools` asset-id chain prefix (`ETH`, `ARB`, …) to a `Chain`.
    /// Returns `nil` for prefixes Vultisig has no EVM wallet support for, so
    /// those pools are dropped at normalization. Only EVM chains are listed —
    /// the static ticker arrays this replaces gate EVM tokens exclusively; L1
    /// native swap providers are not array-gated.
    static func chain(forPoolPrefix prefix: String) -> Chain? {
        switch prefix.uppercased() {
        case "ETH": return .ethereum
        case "ARB": return .arbitrum
        case "BSC": return .bscChain
        case "AVAX": return .avalanche
        case "BASE": return .base
        default: return nil
        }
    }

    /// Parse one `/pools` entry into a normalized `NativePoolAsset`.
    /// Returns `nil` when the asset id is malformed or its chain prefix is
    /// unsupported.
    ///
    /// Asset-id format (verified live): `ETH.USDT-0XDAC17F95…`, `ARB.LEO-0X93…`,
    /// `ETH.ETH` (L1 native, no `-contract`). The contract is uppercased in the
    /// pool id; we lowercase it to compare against `Coin.contractAddress`.
    static func parse(assetId: String, status: String?, tradingHalted: Bool?) -> NativePoolAsset? {
        guard let dotIndex = assetId.firstIndex(of: ".") else { return nil }
        let prefix = String(assetId[..<dotIndex])
        let rest = String(assetId[assetId.index(after: dotIndex)...])
        guard !rest.isEmpty, let poolChain = chain(forPoolPrefix: prefix) else { return nil }

        let ticker: String
        let contract: String?
        if let dashIndex = rest.firstIndex(of: "-") {
            ticker = String(rest[..<dashIndex]).uppercased()
            let rawContract = String(rest[rest.index(after: dashIndex)...])
            contract = rawContract.isEmpty ? nil : rawContract.lowercased()
        } else {
            ticker = rest.uppercased()
            contract = nil
        }
        guard !ticker.isEmpty else { return nil }

        let isAvailable = status.map { $0.caseInsensitiveCompare("Available") == .orderedSame } ?? false
        return NativePoolAsset(
            poolChain: poolChain,
            ticker: ticker,
            contract: contract,
            isAvailable: isAvailable,
            isTradingHalted: tradingHalted ?? false
        )
    }
}
