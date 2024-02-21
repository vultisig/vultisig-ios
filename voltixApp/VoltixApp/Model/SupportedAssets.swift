//
//  SupportedAssets.swift
//  VoltixApp
//

import Foundation
import SwiftData

enum AssetType: CaseIterable {
    case bitcoin
    case ethereum
    case thorchain

    var ticker: String {
        switch self {
        case .bitcoin:
            "BTC"
        case .ethereum:
            "ETH"
        case .thorchain:
            "RUNE"
        }
    }

    var chainName: String {
        switch self {
        case .bitcoin:
            "Bitcoin"
        case .ethereum:
            "Ethereum"
        case .thorchain:
            "THORChain"
        }
    }
}

struct Asset : Codable,Hashable {
    let ticker: String
    let chainName: String
    let image: String
    
    init(ticker: String, chainName: String, image: String) {
        self.ticker = ticker
        self.chainName = chainName
        self.image = image
    }
}
