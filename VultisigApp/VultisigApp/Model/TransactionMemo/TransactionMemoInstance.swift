import SwiftUI
import Foundation
import Combine

enum TransactionMemoInstance {
    case swap(TransactionMemoSwap)
    case depositSavers(TransactionMemoDepositSavers)
    case withdrawSavers(TransactionMemoWithdrawSavers)
    case openLoan(TransactionMemoOpenLoan)
    case repayLoan(TransactionMemoRepayLoan)
    case addLiquidity(TransactionMemoAddLiquidity)
    case withdrawLiquidity(TransactionMemoWithdrawLiquidity)
    case addTradeAccount(TransactionMemoAddTradeAccount)
    case withdrawTradeAccount(TransactionMemoWithdrawTradeAccount)
    case nodeMaintenance(TransactionMemoNodeMaintenance)
    case donateReserve(TransactionMemoDonateReserve)
    case migrate(TransactionMemoMigrate)
    
    var view: AnyView {
        switch self {
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
        case .nodeMaintenance(let memo):
            return memo.getView()
        case .donateReserve(let memo):
            return memo.getView()
        case .migrate(let memo):
            return memo.getView()
        }
    }
    
    var description: String {
        switch self {
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
        case .nodeMaintenance(let memo):
            return memo.description
        case .donateReserve(let memo):
            return memo.description
        case .migrate(let memo):
            return memo.description
        }
    }
}
