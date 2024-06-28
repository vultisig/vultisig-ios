//
//  TransactionMemoContractTypeEnum.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 15/05/24.
//

import SwiftUI
import Foundation
import Combine
import WalletCore

enum TransactionMemoContractType: String, CaseIterable, Identifiable {
    case thorChainMessageDeposit
    case cosmosMessageVote
    
    var id: String { self.rawValue }
    
    func getDescription(for coin: Coin) -> String {
        switch self {
        case .thorChainMessageDeposit:
            return "\(coin.chain.name) message deposit"
        case .cosmosMessageVote:
            return "\(coin.chain.name) message vote"
        }
    }
    
    static func getCases(for coin: Coin) -> [TransactionMemoContractType] {
        switch coin.chain {
        case .thorChain, .mayaChain:
            return [.thorChainMessageDeposit]
        case .dydx:
            return [.cosmosMessageVote]
        default:
            return []
        }
    }
    
    static func getDefault(for coin: Coin) -> TransactionMemoContractType {
        switch coin.chain {
        case .thorChain, .mayaChain:
            return .thorChainMessageDeposit
        case .dydx:
            return .cosmosMessageVote
        default:
            return .thorChainMessageDeposit
        }
    }
}

