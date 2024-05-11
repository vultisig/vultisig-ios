//
//  CoinPaprikaCoin.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 12/04/2024.
//

import Foundation

// Define structs to match the JSON structure
class CoinPaprikaCoin: Decodable {
    let id: String
    let name: String
    let symbol: String
    
    var priceProviderId: String?
}
