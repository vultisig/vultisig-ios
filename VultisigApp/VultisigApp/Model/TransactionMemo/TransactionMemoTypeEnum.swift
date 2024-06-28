//
//  TransactionMemoTypeEnum.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 15/05/24.
//

import SwiftUI
import Foundation
import Combine

enum TransactionMemoType: String, CaseIterable, Identifiable {
    case bond, unbond, leave, custom, vote
    
    var id: String { self.rawValue }
    
    static func getCases(for coin: Coin) -> [TransactionMemoType] {
        switch coin.chain {
        case .thorChain, .mayaChain:
            return [.bond, .unbond, .leave, .custom]
        case .dydx:
            return [.vote]
        case .solana, .ethereum, .avalanche, .base, .blast, .arbitrum, .polygon, .optimism, .bscChain, .cronosChain, .zksync, .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .dash, .gaiaChain, .kujira, .sui, .polkadot:
            return []
        }
    }
    
    static func getDefault(for coin: Coin) -> TransactionMemoType {
        switch coin.chain {
        case .thorChain, .mayaChain:
            return .bond
        case .dydx:
            return .vote
        default:
            return .custom
        }
    }
}
