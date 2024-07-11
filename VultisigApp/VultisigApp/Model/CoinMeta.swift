//
//  CoinMeta.swift
//  VultisigApp
//
//  Created by Johnny Luo on 20/6/2024.
//

import Foundation
import WalletCore

struct CoinMeta : Hashable,Codable{
    let chain: Chain
    let ticker: String
    let logo: String
    let decimals: Int
    let contractAddress: String
    let isNativeToken: Bool
    let priceProviderId: String
    
    init(chain: Chain,
         ticker: String,
         logo: String,
         decimals: Int,
         priceProviderId: String,
         contractAddress: String,
         isNativeToken: Bool) {
        self.chain = chain
        self.ticker = ticker
        self.logo = logo
        self.decimals = decimals
        self.contractAddress = contractAddress
        self.isNativeToken = isNativeToken
        self.priceProviderId = priceProviderId
    }

    var tokenChainLogo: String? {
        guard !isNativeToken else { return nil }
        return chain.logo
    }
    
    var coinType: CoinType {
        return self.chain.coinType
    }

    func coinId(address: String) -> String {
        return "\(chain.rawValue)-\(ticker)-\(address)"
    }
    
    static var example = CoinMeta(chain: .bitcoin, ticker: "BTC", logo: "btc", decimals: 1, priceProviderId: "provider", contractAddress: "123456789", isNativeToken: true)
}

