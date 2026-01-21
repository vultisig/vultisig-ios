//
//  KyberSwapToken.swift
//  VultisigApp
//
//  Created by Enrique Souza on 11.06.2025.
//

import Foundation

struct KyberSwapToken: Codable, Hashable {
    let address: String
    let symbol: String
    let name: String
    let decimals: Int
    let logoURI: String?

    var logoUrl: URL? {
        return logoURI.flatMap { URL(string: $0) }
    }
}

extension KyberSwapToken {
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
