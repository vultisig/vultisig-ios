//
//  ChainType.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 17/03/2024.
//

import Foundation

enum ChainType: Codable, CustomStringConvertible {
    case UTXO
    case Cardano
    case EVM
    case Solana
    case Sui
    case THORChain
    case Cosmos
    case Polkadot
    case Ton
    case Ripple
    case Tron

    var description: String {
        switch self {
        case .UTXO:
            return "Unspent Transaction Output"
        case .Cardano:
            return "Cardano" // Cardano is also UTXO, but uses Ed25519 Cardano, that is why it is separated
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
        case .Ton:
            return "Ton"
        case .Ripple:
            return "Ripple"
        case .Tron:
            return "Tron"
        }
    }
}
