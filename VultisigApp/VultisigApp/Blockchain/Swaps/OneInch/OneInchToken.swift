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

    var logoUrl: URL? {
        return logoURI.flatMap { URL(string: $0) }
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
