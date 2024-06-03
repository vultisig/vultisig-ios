//
//  TokenInfo.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 02/06/24.
//

import Foundation

struct TokenInfo: Decodable {
    let address: String
    let decimals: String
    let name: String
    let owner: String
    let symbol: String
    let totalSupply: String
    let holdersCount: Int
    let website: String
    let image: String
}

struct Token: Decodable {
    let tokenInfo: TokenInfo
    let balance: Int
    let rawBalance: String
    
    func toCoin(chain: Chain, address: String, priceRate: Double) -> Coin {
        return Coin(
            chain: chain,
            ticker: self.tokenInfo.symbol,
            logo: self.tokenInfo.image,
            address: address,
            priceRate: priceRate,
            decimals: Int(self.tokenInfo.decimals) ?? 0,
            hexPublicKey: "", // Assuming this is not available from Token
            priceProviderId: "", // Assuming this is not available from Token
            contractAddress: self.tokenInfo.address,
            rawBalance: self.rawBalance,
            isNativeToken: false // Assuming this is not available from Token
        )
    }
}

