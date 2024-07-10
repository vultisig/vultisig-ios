//
//  SolanaTokenMetadata.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 09/07/24.
//

import Foundation

public struct SolanaFmTokenInfo: Codable {
    struct TokenList: Codable {
        let name: String
        let symbol: String
        let image: String
        let extensions: Extensions
        let chainId: Int
    }
    
    struct Extensions: Codable {
        let coingeckoId: String?
    }
    
    struct TokenMetadata: Codable {
        struct OnChainInfo: Codable {
            let name: String
            let symbol: String
        }
        
        let onChainInfo: OnChainInfo
    }
    
    let mint: String
    let decimals: Int
    let tokenList: TokenList
    let tokenMetadata: TokenMetadata
}
