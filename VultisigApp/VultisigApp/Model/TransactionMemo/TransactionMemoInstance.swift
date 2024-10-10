//
//  TransactionMemoTypeEnum.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 15/05/24.
//

import SwiftUI
import Foundation
import Combine
import VultisigCommonData

enum TransactionMemoInstance {
    case bond(TransactionMemoBond)
    case unbond(TransactionMemoUnbond)
    case leave(TransactionMemoLeave)
    case custom(TransactionMemoCustom)
    case vote(TransactionMemoVote)
    case addPool(TransactionMemoAddPool)
    case withdrawPool(TransactionMemoWithdrawPool)
    
    var view: AnyView {
        switch self {
        case .bond(let memo):
            return memo.getView()
        case .unbond(let memo):
            return memo.getView()
        case .leave(let memo):
            return memo.getView()
        case .custom(let memo):
            return memo.getView()
        case .vote(let memo):
            return memo.getView()
        case .addPool(let memo):
            return memo.getView()
        case .withdrawPool(let memo):
            return memo.getView()
        }
    }
    
    var description: String {
        switch self {
        case .bond(let memo):
            return memo.description
        case .unbond(let memo):
            return memo.description
        case .leave(let memo):
            return memo.description
        case .custom(let memo):
            return memo.description
        case .vote(let memo):
            return memo.description
        case .addPool(let memo):
            return memo.description
        case .withdrawPool(let memo):
            return memo.description
        }
    }
    
    var amount: Double {
        switch self {
        case .bond(let memo):
            return memo.amount
        case .unbond:
            return 1 / pow(10, 8)
        case .leave:
            return 1 / pow(10, 8)
        case .custom(let memo):
            return memo.amount
        case .vote:
            return .zero
        case .addPool(let memo):
            return memo.amount
        case .withdrawPool(_):
            return 0
        }
    }
    
    func toDictionary() -> ThreadSafeDictionary<String, String> {
        switch self {
        case .bond(let memo):
            return memo.toDictionary()
        case .unbond(let memo):
            return memo.toDictionary()
        case .leave(let memo):
            return memo.toDictionary()
        case .custom(let memo):
            return memo.toDictionary()
        case .vote(let memo):
            return memo.toDictionary()
        case .addPool(let memo):
            return memo.toDictionary()
        case .withdrawPool(let memo):
            return memo.toDictionary()
        }
    }
    
    func getTransactionType() -> VSTransactionType {
        switch self {
        case .vote(_):
            return VSTransactionType.vote
        default:
            return .unspecified
        }
    }
    
    var isTheFormValid: Bool {
        switch self {
        case .bond(let memo):
            return memo.isTheFormValid
        case .unbond(let memo):
            return memo.isTheFormValid
        case .leave(let memo):
            return memo.isTheFormValid
        case .custom(let memo):
            return memo.isTheFormValid
        case .vote(let memo):
            return memo.isTheFormValid
        case .addPool(let memo):
            return memo.isTheFormValid
        case .withdrawPool(let memo):
            return memo.isTheFormValid
        }
    }
    
    static func getDefault(for coin: Coin) -> TransactionMemoInstance {
        switch coin.chain {
        case .thorChain, .mayaChain:
            return .bond(TransactionMemoBond())
        case .dydx:
            return .vote(TransactionMemoVote())
        default:
            return .custom(TransactionMemoCustom())
        }
    }
}
