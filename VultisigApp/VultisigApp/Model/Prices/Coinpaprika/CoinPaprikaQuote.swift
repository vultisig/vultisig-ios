//
//  CoinPaprikaResponse.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 12/04/2024.
//

import Foundation

// Define structs to match the JSON structure
class CoinPaprikaQuote: Decodable {
    let id: String
    let name: String
    let symbol: String
    let quotes: [String: CoinPaprikaQuoteDetail]
    
    var priceProviderId: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name, symbol, quotes
    }
}

class CoinPaprikaQuoteDetail: Decodable {
    let price: Double
    
    enum CodingKeys: String, CodingKey {
        case price
    }
}
