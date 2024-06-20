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
    
    func toCoin(address: String, hexPublicKey: String) -> Coin{
        return Coin(
            chain: self.chain,
            ticker: self.ticker,
            logo: self.logo,
            address: address,
            priceRate: 0.0,
            decimals: self.decimals,
            hexPublicKey: hexPublicKey,
            priceProviderId: self.priceProviderId,
            contractAddress: self.contractAddress,
            rawBalance: "0",
            isNativeToken: self.isNativeToken
        )
    }
    var tokenChainLogo: String? {
        guard !isNativeToken else { return nil }
        return chain.logo
    }
    
    var coinType: CoinType {
        return self.chain.coinType
    }
}

