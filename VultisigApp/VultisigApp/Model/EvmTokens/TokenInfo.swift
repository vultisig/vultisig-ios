//
//  TokenInfo.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 02/06/24.
//

import Foundation

//struct TokenInfo: Decodable, Identifiable {
//    var id: String { address }  // Assuming 'address' is unique for each token
//    let address: String
//    let decimals: String
//    let name: String
//    let owner: String
//    let symbol: String
//    let totalSupply: String
//    let holdersCount: Int
//    let website: String?
//    var image: String?
//    
//    mutating func setImage(image: String) {
//        self.image = image
//    }
//}
//
//struct Token: Decodable, Identifiable {
//    var id: String { tokenInfo.address }  // Assuming 'address' is unique for each token
//    var tokenInfo: TokenInfo
//    let balance: Int
//    let rawBalance: String
//    
//    func toCoinMeta(nativeToken: Coin) -> CoinMeta {
//        return CoinMeta(chain: nativeToken.chain,
//                        ticker: self.tokenInfo.symbol,
//                        logo: self.tokenInfo.image ?? .empty,
//                        decimals:Int(self.tokenInfo.decimals) ?? 18,
//                        priceProviderId: .empty,
//                        contractAddress: self.tokenInfo.address,
//                        isNativeToken:false)
//    }
//}
