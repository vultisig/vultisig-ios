//
//  BlockaidSimulationParser.swift
//  VultisigApp
//

import Foundation
import BigInt

/// Translates a Blockaid EVM simulation response into the minimal shape the
/// dApp hero consumes. Mirrors `parseBlockaidEvmSimulation` in
/// vultisig-windows/core/chain/security/blockaid/tx/simulation/api/core.ts.
enum BlockaidSimulationParser {

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

        return parseSwap(diffs: diffs, chain: chain) ?? parseTransfer(diff: diffs[0], chain: chain)
    }

    private static func parseTransfer(
        diff: BlockaidEvmSimulationJson.AssetDiff,
        chain: Chain
    ) -> BlockaidSimulationInfo? {
        guard let out = diff.out?.first,
              let rawValue = out.rawValue,
              let amount = BigInt(rawValue),
              let coin = buildCoin(from: diff.asset, chain: chain) else {
            return nil
        }
        return .transfer(fromCoin: coin, fromAmount: amount)
    }

    private static func parseSwap(
        diffs: [BlockaidEvmSimulationJson.AssetDiff],
        chain: Chain
    ) -> BlockaidSimulationInfo? {
        guard let outDiff = diffs.first(where: { ($0.out?.first?.rawValue) != nil }),
              let inDiff = diffs.first(where: { ($0.in?.first?.rawValue) != nil && $0.asset.address != outDiff.asset.address }) ?? diffs.first(where: { ($0.in?.first?.rawValue) != nil }),
              outDiff.asset.address != inDiff.asset.address || outDiff.asset.symbol != inDiff.asset.symbol,
              let outValueString = outDiff.out?.first?.rawValue,
              let inValueString = inDiff.in?.first?.rawValue,
              let outAmount = BigInt(outValueString),
              let inAmount = BigInt(inValueString),
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
}
