//
//  FunctionCallContractTypeEnum.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 15/05/24.
//

import SwiftUI
import Foundation
import Combine
import WalletCore

enum FunctionCallContractType: String, CaseIterable, Identifiable {
    case thorChainMessageDeposit
    case cosmosMessageVote
    
    var id: String { self.rawValue }
    
    func getDescription(for coin: Coin) -> String {
        switch self {
        case .thorChainMessageDeposit:
            return String(format: NSLocalizedString("messageDeposit", comment: ""), coin.chain.name)
        case .cosmosMessageVote:
            return String(format: NSLocalizedString("messageVote", comment: ""), coin.chain.name)
        }
    }
    
    static func getCases(for coin: Coin) -> [FunctionCallContractType] {
        switch coin.chain {
        case .thorChain, .mayaChain:
            return [.thorChainMessageDeposit]
        case .dydx:
            return [.cosmosMessageVote]
        default:
            return []
        }
    }
    
    static func getDefault(for coin: Coin) -> FunctionCallContractType {
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
