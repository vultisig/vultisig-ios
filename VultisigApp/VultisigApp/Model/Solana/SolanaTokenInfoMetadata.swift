//
//  SolanaTokenMetadata.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 09/07/24.
//

import Foundation

struct SolanaTokenInfoMetadata: Codable {
    let chainId: Int
    let address: String
    let symbol: String
    let name: String
    let decimals: Int
    let logoURI: String
    let tags: [String]?
    let extensions: SolanaTokenInfoMetadataExtension?
}

struct SolanaTokenInfoMetadataExtension: Codable {
    let website: String?
    let bridgeContract: String?
    let assetContract: String?
    let address: String?
    let explorer: String?
    let twitter: String?
    let github: String?
    let medium: String?
    let tgann: String?
    let tggroup: String?
    let discord: String?
    let serumV3Usdc: String?
    let serumV3Usdt: String?
    let coingeckoId: String?
}
