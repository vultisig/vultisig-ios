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
}
