//
//  OneInchToken.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 29.05.2024.
//

import Foundation

struct OneInchToken: Codable, Hashable {
    let address: String
    let symbol: String
    let name: String
    let decimals: Int
    let logoURI: String?
    /// Source-of-truth list from 1inch's `/token/v1.2/{chain}/custom` response.
    /// The EVM coin-finder requires `providers.contains("CoinGecko")` as a
    /// legitimacy signal — matches the SDK's `findEvmCoins` filter (see
    /// vultisig-sdk/packages/core/chain/coin/find/resolvers/evm/index.ts:69).
    let providers: [String]?

    var logoUrl: URL? {
        return logoURI.flatMap { URL(string: $0) }
    }

    var isCoinGeckoVerified: Bool {
        providers?.contains("CoinGecko") ?? false
    }
}

extension OneInchToken {
    func toCoinMeta(chain: Chain) -> CoinMeta {
        return CoinMeta(chain: chain,
                        ticker: self.symbol,
                        logo: self.logoURI ?? "",
                        decimals: self.decimals,
                        priceProviderId: .empty,
                        contractAddress: self.address,
                        isNativeToken: false)
    }

    /// Trust-carrying catalog candidate. Unlike `toCoinMeta` (which drops the
    /// legitimacy signal), this preserves 1inch's CoinGecko-verified flag as the
    /// token's `verification` — the same signal `EvmCoinFinder` uses as its scam
    /// gate. Note: 1inch `/tokens` carries no CoinGecko id, so `priceProviderId`
    /// stays empty; the curated bundled provider wins dedup and supplies it for
    /// known tokens.
    func toCatalogToken(chain: Chain, sourceKind: String) -> CatalogToken {
        let verification: TokenVerification = isCoinGeckoVerified
            ? .verified(source: "CoinGecko")
            : .unverified
        return CatalogToken(meta: toCoinMeta(chain: chain), verification: verification, sourceKind: sourceKind)
    }
}
