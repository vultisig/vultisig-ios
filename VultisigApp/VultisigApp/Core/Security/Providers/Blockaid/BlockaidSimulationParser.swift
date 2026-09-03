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

    /// Parses every Solana balance leg into complete per-mint net changes.
    /// Native SOL and WSOL share the wrapped-SOL mint sentinel, so wrapping
    /// noise is netted while distinct assets remain independent. A hero is
    /// emitted only when the complete result is one transfer/receive or one
    /// unambiguous swap; multi-spend shapes fail closed.
    static func parseSolana(
        response: BlockaidSolanaSimulationResponseJson
    ) -> BlockaidSimulationInfo? {
        guard let diffs = response.result?.simulation?.accountSummary?.accountAssetsDiff,
              !diffs.isEmpty else {
            return nil
        }

        return parseSolanaNetChanges(diffs: diffs)
    }

    private struct SolanaMintBalance {
        let decimals: Int
        var incoming: BigInt = 0
        var outgoing: BigInt = 0
        var incomingCoin: BlockaidSimulationCoin?
        var outgoingCoin: BlockaidSimulationCoin?
    }

    private struct SolanaNetChange {
        let coin: BlockaidSimulationCoin
        let amount: BigInt
    }

    private static func parseSolanaNetChanges(
        diffs: [BlockaidSolanaSimulationJson.AccountAssetDiff]
    ) -> BlockaidSimulationInfo? {
        guard let balances = solanaMintBalances(diffs: diffs) else { return nil }

        var incomingChanges: [SolanaNetChange] = []
        var outgoingChanges: [SolanaNetChange] = []

        for balance in balances.values {
            if balance.outgoing > balance.incoming,
               let coin = balance.outgoingCoin {
                outgoingChanges.append(
                    SolanaNetChange(coin: coin, amount: balance.outgoing - balance.incoming)
                )
            } else if balance.incoming > balance.outgoing,
                      let coin = balance.incomingCoin {
                incomingChanges.append(
                    SolanaNetChange(coin: coin, amount: balance.incoming - balance.outgoing)
                )
            }
        }

        if outgoingChanges.count == 1, incomingChanges.isEmpty,
           let outgoing = outgoingChanges.first {
            return .transfer(fromCoin: outgoing.coin, fromAmount: outgoing.amount)
        }

        if outgoingChanges.isEmpty, incomingChanges.count == 1,
           let incoming = incomingChanges.first {
            return .receive(coin: incoming.coin, amount: incoming.amount)
        }

        if outgoingChanges.count == 1, incomingChanges.count == 1,
           let outgoing = outgoingChanges.first,
           let incoming = incomingChanges.first {
            return .swap(
                fromCoin: outgoing.coin,
                toCoin: incoming.coin,
                fromAmount: outgoing.amount,
                toAmount: incoming.amount
            )
        }

        return nil
    }

    private static func solanaMintBalances(
        diffs: [BlockaidSolanaSimulationJson.AccountAssetDiff]
    ) -> [String: SolanaMintBalance]? {
        var balances: [String: SolanaMintBalance] = [:]

        for diff in diffs {
            let isNativeSol = diff.asset.type == "SOL" || diff.assetType == "SOL"
            guard let incoming = parseSolanaLeg(diff.`in`),
                  let outgoing = parseSolanaLeg(diff.out) else {
                return nil
            }
            guard incoming != 0 || outgoing != 0 else { continue }
            guard let coin = buildSolanaCoin(from: diff.asset, assetType: diff.assetType),
                  let mint = coin.address else {
                return nil
            }

            if var balance = balances[mint] {
                guard balance.decimals == coin.decimals else { return nil }
                balance.incoming += incoming
                balance.outgoing += outgoing
                if incoming > 0, balance.incomingCoin == nil || isNativeSol {
                    balance.incomingCoin = coin
                }
                if outgoing > 0, balance.outgoingCoin == nil || isNativeSol {
                    balance.outgoingCoin = coin
                }
                balances[mint] = balance
            } else {
                balances[mint] = SolanaMintBalance(
                    decimals: coin.decimals,
                    incoming: incoming,
                    outgoing: outgoing,
                    incomingCoin: incoming > 0 ? coin : nil,
                    outgoingCoin: outgoing > 0 ? coin : nil
                )
            }
        }

        return balances
    }

    /// Missing legs are zero; present legs must decode to a non-negative
    /// magnitude because direction is carried by the `in`/`out` field itself.
    private static func parseSolanaLeg(
        _ leg: BlockaidSolanaSimulationJson.BalanceChange?
    ) -> BigInt? {
        guard let leg else { return 0 }
        guard let raw = leg.rawValue,
              let amount = parseRawAmount(raw),
              amount >= 0 else {
            return nil
        }
        return amount
    }

    /// Builds a `BlockaidSimulationCoin` from a Solana asset, substituting the
    /// wrapped-SOL mint for native SOL. Prefers Blockaid-returned metadata;
    /// falls back to `TokensStore` and finally to a truncated mint when symbol
    /// is missing. Decimals must come from one of Blockaid or TokensStore.
    private static func buildSolanaCoin(
        from asset: BlockaidSolanaSimulationJson.Asset,
        assetType: String?
    ) -> BlockaidSimulationCoin? {
        let isNative = asset.type == "SOL" || assetType == "SOL"
        let mint = isNative ? wrappedSolMint : asset.address
        guard let mint, !mint.isEmpty else { return nil }

        // Native SOL would otherwise match the wrapped-SOL (WSOL) metadata via
        // the mint sentinel — skip the lookup and use the chain's native logo
        // directly so the hero renders "SOL" with the proper icon.
        let storeMatch = isNative
            ? nil
            : TokensStore.findTokenMeta(chain: .solana, contractAddress: mint)

        guard let decimals = asset.decimals ?? storeMatch?.decimals else {
            return nil
        }

        let ticker = asset.symbol ?? storeMatch?.ticker ?? truncatedMint(mint)
        // Blockaid returns per-request logo URLs under cdn.blockaid.io that are
        // not hot-linkable, so the AsyncImageView placeholder would spin forever.
        // Prefer the native Solana asset for SOL, the TokensStore asset for
        // known SPL tokens, and only fall back to Blockaid's URL when nothing
        // local matches.
        let logo: String
        if isNative {
            logo = Chain.solana.logo
        } else {
            logo = storeMatch?.logo ?? asset.logo ?? .empty
        }

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
