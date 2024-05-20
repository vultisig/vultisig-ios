//
//  TransactionMemoTypeEnum.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 15/05/24.
//

import SwiftUI
import Foundation
import Combine

enum TransactionMemoInstance {
    case bond(TransactionMemoBond)
    case unbond(TransactionMemoUnbond)
    case leave(TransactionMemoLeave)
    case swap(TransactionMemoSwap)
    case depositSavers(TransactionMemoDepositSavers)
    case withdrawSavers(TransactionMemoWithdrawSavers)
    case openLoan(TransactionMemoOpenLoan)
    case repayLoan(TransactionMemoRepayLoan)
    case addLiquidity(TransactionMemoAddLiquidity)
    case withdrawLiquidity(TransactionMemoWithdrawLiquidity)
    case addTradeAccount(TransactionMemoAddTradeAccount)
    case withdrawTradeAccount(TransactionMemoWithdrawTradeAccount)
    case donateReserve(TransactionMemoDonateReserve)
    case migrate(TransactionMemoMigrate)
    
    var view: AnyView {
        switch self {
        case .bond(let memo):
            return memo.getView()
        case .unbond(let memo):
            return memo.getView()
        case .leave(let memo):
            return memo.getView()
        case .swap(let memo):
            return memo.getView()
        case .depositSavers(let memo):
            return memo.getView()
        case .withdrawSavers(let memo):
            return memo.getView()
        case .openLoan(let memo):
            return memo.getView()
        case .repayLoan(let memo):
            return memo.getView()
        case .addLiquidity(let memo):
            return memo.getView()
        case .withdrawLiquidity(let memo):
            return memo.getView()
        case .addTradeAccount(let memo):
            return memo.getView()
        case .withdrawTradeAccount(let memo):
            return memo.getView()
        case .donateReserve(let memo):
            return memo.getView()
        case .migrate(let memo):
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
        case .swap(let memo):
            return memo.description
        case .depositSavers(let memo):
            return memo.description
        case .withdrawSavers(let memo):
            return memo.description
        case .openLoan(let memo):
            return memo.description
        case .repayLoan(let memo):
            return memo.description
        case .addLiquidity(let memo):
            return memo.description
        case .withdrawLiquidity(let memo):
            return memo.description
        case .addTradeAccount(let memo):
            return memo.description
        case .withdrawTradeAccount(let memo):
            return memo.description
        case .donateReserve(let memo):
            return memo.description
        case .migrate(let memo):
            return memo.description
        }
    }
    
    //TODO: Check if others need amount if not keep it as zero
    var amount: Double {
        switch self {
        case .bond(let memo):
            return memo.amount
        case .unbond(let memo):
            return memo.amount
        case .leave(let memo):
            return .zero
        case .swap(let memo):
            return .zero
        case .depositSavers(let memo):
            return .zero
        case .withdrawSavers(let memo):
            return .zero
        case .openLoan(let memo):
            return .zero
        case .repayLoan(let memo):
            return .zero
        case .addLiquidity(let memo):
            return .zero
        case .withdrawLiquidity(let memo):
            return .zero
        case .addTradeAccount(let memo):
            return .zero
        case .withdrawTradeAccount(let memo):
            return .zero
        case .donateReserve(let memo):
            return .zero
        case .migrate(let memo):
            return .zero
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
        case .swap(let memo):
            return memo.toDictionary()
        case .depositSavers(let memo):
            return memo.toDictionary()
        case .withdrawSavers(let memo):
            return memo.toDictionary()
        case .openLoan(let memo):
            return memo.toDictionary()
        case .repayLoan(let memo):
            return memo.toDictionary()
        case .addLiquidity(let memo):
            return memo.toDictionary()
        case .withdrawLiquidity(let memo):
            return memo.toDictionary()
        case .addTradeAccount(let memo):
            return memo.toDictionary()
        case .withdrawTradeAccount(let memo):
            return memo.toDictionary()
        case .donateReserve(let memo):
            return memo.toDictionary()
        case .migrate(let memo):
            return memo.toDictionary()
        }
    }
}
