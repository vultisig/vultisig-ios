//
//  TransactionMemoTypeEnum.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 15/05/24.
//

import Combine
import Foundation
import SwiftUI
import VultisigCommonData

enum TransactionMemoInstance {
    case bond(TransactionMemoBond)
    case unbond(TransactionMemoUnbond)
    case bondMaya(TransactionMemoBondMayaChain)
    case unbondMaya(TransactionMemoUnbondMayaChain)
    case leave(TransactionMemoLeave)
    case custom(TransactionMemoCustom)
    case vote(TransactionMemoVote)
    case stake(TransactionMemoStake)
    case unstake(TransactionMemoUnstake)

    var view: AnyView {
        switch self {
        case .bond(let memo):
            return memo.getView()
        case .unbond(let memo):
            return memo.getView()
        case .bondMaya(let memo):
            return memo.getView()
        case .unbondMaya(let memo):
            return memo.getView()
        case .leave(let memo):
            return memo.getView()
        case .custom(let memo):
            return memo.getView()
        case .vote(let memo):
            return memo.getView()
        case .stake(let memo):
            return memo.getView()
        case .unstake(let memo):
            return memo.getView()
        }
    }

    var description: String {
        switch self {
        case .bond(let memo):
            return memo.description
        case .unbond(let memo):
            return memo.description
        case .bondMaya(let memo):
            return memo.description
        case .unbondMaya(let memo):
            return memo.description
        case .leave(let memo):
            return memo.description
        case .custom(let memo):
            return memo.description
        case .vote(let memo):
            return memo.description
        case .stake(let memo):
            return memo.description
        case .unstake(let memo):
            return memo.description
        }
    }

    var amount: Double {
        switch self {
        case .bond(let memo):
            return memo.amount
        case .unbond:
            return .zero
        case .bondMaya(let memo):
            return memo.amount
        case .unbondMaya:
            return 1 / pow(10, 8)
        case .leave:
            return .zero
        case .custom(let memo):
            return memo.amount
        case .vote:
            return .zero
        case .stake(let memo):
            return memo.amount
        case .unstake(let memo):
            return memo.amount  // You must send 1 TON to unstake with a "w" memo
        }
    }

    var toAddress: String? {
        switch self {
        case .stake(let memo):
            return memo.nodeAddress
        case .unstake(let memo):
            return memo.nodeAddress
        default:
            return nil
        }
    }

    func toDictionary() -> ThreadSafeDictionary<String, String> {
        switch self {
        case .bond(let memo):
            return memo.toDictionary()
        case .unbond(let memo):
            return memo.toDictionary()
        case .bondMaya(let memo):
            return memo.toDictionary()
        case .unbondMaya(let memo):
            return memo.toDictionary()
        case .leave(let memo):
            return memo.toDictionary()
        case .custom(let memo):
            return memo.toDictionary()
        case .vote(let memo):
            return memo.toDictionary()
        case .stake(let memo):
            return memo.toDictionary()
        case .unstake(let memo):
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
        case .bondMaya(let memo):
            return memo.isTheFormValid
        case .unbondMaya(let memo):
            return memo.isTheFormValid
        case .leave(let memo):
            return memo.isTheFormValid
        case .custom(let memo):
            return memo.isTheFormValid
        case .vote(let memo):
            return memo.isTheFormValid
        case .stake(let memo):
            return memo.isTheFormValid
        case .unstake(let memo):
            return memo.isTheFormValid
        }
    }

    static func getDefault(for coin: Coin, tx: SendTransaction, transactionMemoViewModel: TransactionMemoViewModel) -> TransactionMemoInstance {
        switch coin.chain {
        case .thorChain:
            return .bond(TransactionMemoBond(tx: tx, transactionMemoViewModel: transactionMemoViewModel))
        case .mayaChain:
            return .bondMaya(TransactionMemoBondMayaChain(assets: nil))
        case .dydx:
            return .vote(TransactionMemoVote())
        case .ton:
            return .stake(TransactionMemoStake())
        default:
            return .custom(TransactionMemoCustom())
        }
    }
}
