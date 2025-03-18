//
//  ElDoritoToken.swift
//  VoltixApp
//
//  Created by Enrique Souza
//

import Foundation

struct ElDoritoToken: Codable, Hashable {
    let address: String?
    let ticker: String
    let decimals: Int
    let logoURI: String?
    let chain: String
    let identifier: String
    let chainId: String // Change from `Int` to `String`
    let coingeckoId: String?
    
    var logoURL: URL? {
        return logoURI.flatMap { URL(string: $0) }
    }
}
