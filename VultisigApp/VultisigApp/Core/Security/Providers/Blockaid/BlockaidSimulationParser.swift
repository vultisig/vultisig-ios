//
//  BlockaidSimulationParser.swift
//  VultisigApp
//

import Foundation
import BigInt

/// Translates a Blockaid EVM or Solana simulation response into the minimal
/// shape the dApp hero consumes. Mirrors `parseBlockaidEvmSimulation` and
/// `parseBlockaidSolanaSimulation` in
/// vultisig-windows/core/chain/security/blockaid/tx/simulation/api/core.ts.
enum BlockaidSimulationParser {

    /// Sentinel mint used to represent native SOL in simulation output. This
    /// is the SPL wrapped-SOL mint and matches the extension's behaviour so
    /// TokensStore lookups work uniformly for native and wrapped SOL.
    static let wrappedSolMint = "So11111111111111111111111111111111111111112"

    static func parse(
        response: BlockaidEvmSimulationResponseJson,
        chain: Chain
    ) -> BlockaidSimulationInfo? {
        guard let simulation = response.simulation,
              let diffs = simulation.accountSummary?.assetsDiffs,
              !diffs.isEmpty else {
            return nil
        }

        if diffs.count == 1 {
            return parseTransfer(diff: diffs[0], chain: chain)
        }

        return parseSwap(diffs: diffs, chain: chain)
    }

    private static func parseTransfer(
        diff: BlockaidEvmSimulationJson.AssetDiff,
        chain: Chain
    ) -> BlockaidSimulationInfo? {
        guard let out = diff.out?.first,
              let rawValue = out.rawValue,
              let amount = parseRawAmount(rawValue),
              let coin = buildCoin(from: diff.asset, chain: chain) else {
            return nil
        }
        return .transfer(fromCoin: coin, fromAmount: amount)
    }

    private static func parseSwap(
        diffs: [BlockaidEvmSimulationJson.AssetDiff],
        chain: Chain
    ) -> BlockaidSimulationInfo? {
        // EVM addresses are case-insensitive (EIP-55 checksums differ in casing
        // between otherwise-identical addresses), so compare lowercased.
        guard let outDiff = diffs.first(where: { ($0.out?.first?.rawValue) != nil }),
              let inDiff = diffs.first(where: { ($0.in?.first?.rawValue) != nil && $0.asset.address?.lowercased() != outDiff.asset.address?.lowercased() }) ?? diffs.first(where: { ($0.in?.first?.rawValue) != nil }),
              outDiff.asset.address?.lowercased() != inDiff.asset.address?.lowercased() || outDiff.asset.symbol != inDiff.asset.symbol,
              let outValueString = outDiff.out?.first?.rawValue,
              let inValueString = inDiff.in?.first?.rawValue,
              let outAmount = parseRawAmount(outValueString),
              let inAmount = parseRawAmount(inValueString),
              let fromCoin = buildCoin(from: outDiff.asset, chain: chain),
              let toCoin = buildCoin(from: inDiff.asset, chain: chain) else {
            return nil
        }

        return .swap(
            fromCoin: fromCoin,
            toCoin: toCoin,
            fromAmount: outAmount,
            toAmount: inAmount
        )
    }

    /// Blockaid encodes `raw_value` as a hex string (e.g. `"0x75652c52418a6"`).
    /// `BigInt(_:)` in Swift defaults to base 10 and would return nil for
    /// hex-prefixed values. Accept both to stay tolerant of any non-hex
    /// payloads the backend might return.
    private static func parseRawAmount(_ raw: String) -> BigInt? {
        if raw.hasPrefix("0x") || raw.hasPrefix("0X") {
            return BigInt(raw.dropFirst(2), radix: 16)
        }
        return BigInt(raw)
    }

    private static func buildCoin(
        from asset: BlockaidEvmSimulationJson.Asset,
        chain: Chain
    ) -> BlockaidSimulationCoin? {
        guard let symbol = asset.symbol, let decimals = asset.decimals else {
            return nil
        }
        return BlockaidSimulationCoin(
            chain: chain,
            address: asset.address,
            ticker: symbol,
            logo: asset.logoUrl ?? .empty,
            decimals: decimals
        )
    }

    // MARK: - Solana

    /// Parses a Solana simulation response. Mirrors `parseBlockaidSolanaSimulation`:
    /// when three diffs come back and one is native SOL, the SOL diff is
    /// filtered out as "likely the transaction fee". One remaining diff maps to
    /// `.transfer`, two remaining diffs map to `.swap` (or `.transfer` if only
    /// the out side has a value).
    static func parseSolana(
        response: BlockaidSolanaSimulationResponseJson
    ) -> BlockaidSimulationInfo? {
        guard let diffs = response.result?.simulation?.accountSummary?.accountAssetsDiff,
              !diffs.isEmpty else {
            return nil
        }

        let relevant: [BlockaidSolanaSimulationJson.AccountAssetDiff]
        if diffs.count == 3,
           let solIndex = diffs.firstIndex(where: { $0.asset.type == "SOL" || $0.assetType == "SOL" }) {
            var filtered = diffs
            filtered.remove(at: solIndex)
            relevant = filtered
        } else {
            relevant = diffs
        }

        if relevant.count == 1 {
            return parseSolanaTransfer(diff: relevant[0])
        }

        return parseSolanaSwap(diffs: relevant)
    }

    private static func parseSolanaTransfer(
        diff: BlockaidSolanaSimulationJson.AccountAssetDiff
    ) -> BlockaidSimulationInfo? {
        guard let rawValue = diff.out?.rawValue,
              let amount = parseRawAmount(rawValue),
              let coin = buildSolanaCoin(from: diff.asset) else {
            return nil
        }
        return .transfer(fromCoin: coin, fromAmount: amount)
    }

    private static func parseSolanaSwap(
        diffs: [BlockaidSolanaSimulationJson.AccountAssetDiff]
    ) -> BlockaidSimulationInfo? {
        // Mirror the extension's positional destructuring: first diff is the
        // out side, second is the in side. Fall back to .transfer when only
        // one side carries a value (matches the extension's `else if` branch).
        let outCandidate = diffs[0]
        let inCandidate = diffs[1]

        let inSource = inCandidate.`in` != nil ? inCandidate : outCandidate
        let outSource = outCandidate.out != nil ? outCandidate : inCandidate

        if let outRaw = outSource.out?.rawValue,
           let inRaw = inSource.`in`?.rawValue,
           let outAmount = parseRawAmount(outRaw),
           let inAmount = parseRawAmount(inRaw),
           let fromCoin = buildSolanaCoin(from: outSource.asset),
           let toCoin = buildSolanaCoin(from: inSource.asset) {
            return .swap(fromCoin: fromCoin, toCoin: toCoin, fromAmount: outAmount, toAmount: inAmount)
        }

        if let outRaw = outSource.out?.rawValue,
           let outAmount = parseRawAmount(outRaw),
           let fromCoin = buildSolanaCoin(from: outSource.asset) {
            return .transfer(fromCoin: fromCoin, fromAmount: outAmount)
        }

        return nil
    }

    /// Builds a `BlockaidSimulationCoin` from a Solana asset, substituting the
    /// wrapped-SOL mint for native SOL. Prefers Blockaid-returned metadata;
    /// falls back to `TokensStore` and finally to a truncated mint when symbol
    /// is missing. Decimals must come from one of Blockaid or TokensStore.
    private static func buildSolanaCoin(
        from asset: BlockaidSolanaSimulationJson.Asset
    ) -> BlockaidSimulationCoin? {
        let mint = asset.type == "SOL" ? wrappedSolMint : asset.address
        guard let mint, !mint.isEmpty else { return nil }

        let storeMatch = TokensStore.findTokenMeta(chain: .solana, contractAddress: mint)

        guard let decimals = asset.decimals ?? storeMatch?.decimals else {
            return nil
        }

        let ticker = asset.symbol ?? storeMatch?.ticker ?? truncatedMint(mint)
        // Blockaid returns per-request logo URLs under cdn.blockaid.io that are
        // not hot-linkable, so the AsyncImageView placeholder would spin forever.
        // Prefer the local TokensStore asset; fall back to Blockaid's URL only
        // when we have no match, and ultimately let the view's first-letter
        // fallback render if no logo resolves.
        let logo = storeMatch?.logo ?? asset.logo ?? .empty

        return BlockaidSimulationCoin(
            chain: .solana,
            address: mint,
            ticker: ticker,
            logo: logo,
            decimals: decimals
        )
    }

    private static func truncatedMint(_ mint: String) -> String {
        guard mint.count > 8 else { return mint }
        return "\(mint.prefix(4))…\(mint.suffix(4))"
    }
}
