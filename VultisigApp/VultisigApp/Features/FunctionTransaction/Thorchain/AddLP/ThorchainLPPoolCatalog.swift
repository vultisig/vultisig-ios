//
//  ThorchainLPPoolCatalog.swift
//  VultisigApp
//
//  Which pools a chain offers a liquidity deposit into, and which asset each of
//  them deposits.
//
//  Pure functions over values so the selection rules — the ones that decide
//  what the memo names and which asset leaves the wallet — are testable without
//  a network or a store.
//

import Foundation

enum ThorchainLPPoolCatalog {

    /// The pools on `chain` this vault can actually deposit into, in the order
    /// THORChain lists them.
    ///
    /// Filtered to pools whose asset the vault holds, and that filter is a fix
    /// rather than a convenience. The dropdown this replaces listed every pool
    /// on the chain and then silently declined to switch the source asset when
    /// the vault did not hold the pool's token — leaving the previously
    /// selected asset paying for a memo that names a different one. A pool the
    /// wallet cannot fund is not an option, so it is not offered.
    ///
    /// Each entry carries the pool's full THORChain name, contract suffix
    /// included, because that is the string the memo must contain; the picker
    /// shows the asset, so the display side needs no cleaning of its own.
    static func depositablePools(
        on chain: Chain,
        pools: [ThorchainPool],
        holdings: [Coin]
    ) -> [THORChainAsset] {
        let swapAsset = chain.swapAsset.uppercased()
        return pools.compactMap { pool in
            let components = pool.asset.split(separator: ".").map { String($0).uppercased() }
            guard components.count >= 2, components[0] == swapAsset else { return nil }
            guard let coin = depositCoin(forPool: pool.asset, in: holdings) else { return nil }
            return THORChainAsset(thorchainAsset: pool.asset, asset: coin.toCoinMeta())
        }
    }

    /// The vault coin a pool selection deposits, or nil when the vault holds no
    /// such asset.
    ///
    /// ⚠️ Matched on the chain, the ticker **and the contract**, because a
    /// ticker is not an identity. THORChain names a token pool
    /// `ETH.USDC-0X<contract>`, and that contract is what makes it *the* USDC
    /// pool; a vault can hold more than one token calling itself USDC on the
    /// same chain, and a wallet that picked the first ticker match would
    /// transfer the wrong token against a memo naming the real pool's contract.
    /// THORChain would credit nothing and the funds would be stranded at an
    /// inbound vault.
    ///
    /// A pool with no contract suffix is a chain's own asset — `ETH.ETH`,
    /// `BSC.BNB`, `BTC.BTC` — so it must resolve a native coin and never a
    /// token that happens to share the ticker.
    ///
    /// That last rule is right for every chain this is reachable from, all of
    /// which name their tokens with a contract. It would be wrong on THORChain
    /// itself, where a native-side asset like `THOR.TCY` is suffix-less and not
    /// the gas asset — so a THORChain-side pool picker would need to relax it.
    /// There is no such picker: a RUNE-side deposit arrives with its pool
    /// already fixed by the position card.
    static func depositCoin(forPool poolAsset: String, in holdings: [Coin]) -> Coin? {
        let components = poolAsset.split(separator: ".").map { String($0).uppercased() }
        guard components.count >= 2 else { return nil }
        let chainPrefix = components[0]

        let assetParts = components[1].split(separator: "-", maxSplits: 1).map(String.init)
        guard let ticker = assetParts.first, ticker.isNotEmpty else { return nil }
        let contract = assetParts.count > 1 ? assetParts[1] : nil

        return holdings.first { coin in
            guard coin.chain.swapAsset.uppercased() == chainPrefix,
                  coin.ticker.uppercased() == ticker else {
                return false
            }
            guard let contract else { return coin.isNativeToken }
            return !coin.isNativeToken && coin.contractAddress.uppercased() == contract
        }
    }
}
