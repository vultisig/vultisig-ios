//
//  SupportedAssets.swift
//  VoltixApp
//

import Foundation

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

