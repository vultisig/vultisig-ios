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
    ///
    /// Diverges from the extension in one place: a two-diff pair that resolves
    /// to the same mint is netted rather than reported as a swap — see
    /// `netSameMint(outCoin:outAmount:inCoin:inAmount:)`.
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
        let outIndex = diffs[0].out != nil ? 0 : 1
        let inIndex = diffs[1].`in` != nil ? 1 : 0
        let outSource = diffs[outIndex]
        let inSource = diffs[inIndex]

        if let outRaw = outSource.out?.rawValue,
           let inRaw = inSource.`in`?.rawValue,
           let outAmount = parseRawAmount(outRaw),
           let inAmount = parseRawAmount(inRaw),
           let fromCoin = buildSolanaCoin(from: outSource.asset),
           let toCoin = buildSolanaCoin(from: inSource.asset) {
            if let outMint = fromCoin.address,
               let inMint = toCoin.address,
               outMint == inMint {
                // The netting reads exactly two legs: one diff's out side and
                // one diff's in side, which can collapse onto the same diff.
                // Every other leg the response states goes unread, so netting
                // past one would have the hero state an authoritative net
                // having never looked at a balance change the transaction
                // makes. Decline and let the caller fall back to the generic
                // title.
                guard readsEveryLeg(diffs, outIndex: outIndex, inIndex: inIndex) else {
                    return nil
                }
                return netSameMint(
                    outCoin: fromCoin,
                    outAmount: outAmount,
                    inCoin: toCoin,
                    inAmount: inAmount
                )
            }
            return .swap(fromCoin: fromCoin, toCoin: toCoin, fromAmount: outAmount, toAmount: inAmount)
        }

        if let outRaw = outSource.out?.rawValue,
           let outAmount = parseRawAmount(outRaw),
           let fromCoin = buildSolanaCoin(from: outSource.asset) {
            return .transfer(fromCoin: fromCoin, fromAmount: outAmount)
        }

        return nil
    }

    /// Collapses an out/in pair that resolves to a single mint into the net
    /// movement of that mint.
    ///
    /// Nothing was exchanged, so a swap hero would name a destination asset the
    /// user is not receiving. Wrapping SOL and spending it in the same
    /// transaction is the common source: the wrap-in and the spend-out cancel
    /// and never surface as diffs of their own, leaving only the wSOL account's
    /// rent-exempt residual as a small incoming diff beside the real native-SOL
    /// out leg. `buildSolanaCoin` maps native SOL onto the wrapped-SOL mint, so
    /// both legs arrive here carrying the same mint and are directly netted.
    ///
    /// The direction is decided by the net, not by which leg is which: the same
    /// pair arrives reversed when a transaction unwraps wSOL back into native
    /// SOL (a Kamino wrapped-SOL withdraw closes its payout account, which is
    /// what unwraps it), where the out leg is only the residual being returned
    /// and the in leg is the amount the user actually receives. The coin comes
    /// from whichever leg the net follows, so the ticker stays truthful —
    /// native SOL reads "SOL" even though it shares WSOL's mint here.
    ///
    /// An exact cancellation nets to zero. There is no honest hero for "your
    /// balance does not change", so it returns nil and the caller falls back to
    /// the generic title.
    ///
    /// Mints are compared exactly. Solana addresses are base58 and
    /// case-sensitive, unlike the EVM path's checksummed hex.
    ///
    /// Both legs must be non-negative. Blockaid states each side's magnitude
    /// and puts the direction in the field name, but `raw_value` decodes a
    /// signed integer, and a negative reaching the subtraction would flip the
    /// direction of an approval headline. Fail closed instead.
    private static func netSameMint(
        outCoin: BlockaidSimulationCoin,
        outAmount: BigInt,
        inCoin: BlockaidSimulationCoin,
        inAmount: BigInt
    ) -> BlockaidSimulationInfo? {
        guard outAmount >= 0, inAmount >= 0 else { return nil }

        if outAmount > inAmount {
            return .transfer(fromCoin: outCoin, fromAmount: outAmount - inAmount)
        }
        if inAmount > outAmount {
            return .receive(coin: inCoin, amount: inAmount - outAmount)
        }
        return nil
    }

    /// Whether the netting's two legs are the only balance changes the
    /// response states.
    ///
    /// The netting subtracts `diffs[inIndex].in` from `diffs[outIndex].out`
    /// and reads nothing else — not the out leg of any other diff, nor the in
    /// leg of any other diff, and not the opposite leg of either source when
    /// the two indices differ. Any of those carrying a balance means the net
    /// on screen would be missing an amount the transaction moves, which is
    /// worse than no net at all.
    private static func readsEveryLeg(
        _ diffs: [BlockaidSolanaSimulationJson.AccountAssetDiff],
        outIndex: Int,
        inIndex: Int
    ) -> Bool {
        diffs.indices.allSatisfy { index in
            (index == outIndex || !carriesBalance(diffs[index].out))
                && (index == inIndex || !carriesBalance(diffs[index].`in`))
        }
    }

    /// Whether a single leg states a balance change.
    ///
    /// A leg that decodes to zero moves nothing, so it is not a change the
    /// netting has to account for — declining over one would drop a net the
    /// hero could state honestly. A leg that is present but whose magnitude
    /// does not decode is not provably zero (`BalanceChange` keeps a
    /// `raw_value` it cannot read as nil), so it counts as a change and the
    /// netting fails closed.
    private static func carriesBalance(
        _ leg: BlockaidSolanaSimulationJson.BalanceChange?
    ) -> Bool {
        guard let leg else { return false }
        guard let raw = leg.rawValue, let amount = parseRawAmount(raw) else { return true }
        return amount != 0
    }

    /// Builds a `BlockaidSimulationCoin` from a Solana asset, substituting the
    /// wrapped-SOL mint for native SOL. Prefers Blockaid-returned metadata;
    /// falls back to `TokensStore` and finally to a truncated mint when symbol
    /// is missing. Decimals must come from one of Blockaid or TokensStore.
    private static func buildSolanaCoin(
        from asset: BlockaidSolanaSimulationJson.Asset
    ) -> BlockaidSimulationCoin? {
        let isNative = asset.type == "SOL"
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
