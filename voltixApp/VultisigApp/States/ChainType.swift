//
//  ChainType.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 17/03/2024.
//

import Foundation

enum ChainType: Codable, CustomStringConvertible {
    case UTXO
    case EVM
    case Solana
    case Sui
    case THORChain
    case Cosmos
    case Polkadot
    
    var description: String {
        switch self {
        case .UTXO:
            return "Unspent Transaction Output"
        case .EVM:
            return "Ethereum Virtual Machine"
        case .Solana:
            return "Solana"
        case .Sui:
            return "Sui"
        case .THORChain:
            return "THORChain"
        case .Cosmos:
            return "Cosmos"
        case .Polkadot:
            return "Polkadot"
        }
    }
}
