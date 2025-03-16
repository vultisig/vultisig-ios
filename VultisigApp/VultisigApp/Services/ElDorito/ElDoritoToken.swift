//
//  OneInchToken.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 29.05.2024.
//

import Foundation

struct ElDoritoToken: Codable, Hashable {
    let address: String
    let ticker: String
    let symbol: String
    let name: String
    let decimals: Int
    let logoURI: String?
    let chain: String
    let identifier: String
    let chainId: Int
    let coingeckoId: String?

    var logoURl: URL? {
        return logoURI.flatMap { URL(string: $0) }
    }
}

extension ElDoritoToken {
    func toCoinMeta(chain: Chain) -> CoinMeta {
        return CoinMeta(chain: chain,
                        ticker: self.ticker,
                        logo: self.logoURI ?? "",
                        decimals: self.decimals,
                        priceProviderId: coingeckoId ?? "",
                        contractAddress: self.address,
                        isNativeToken: false)
    }
}
