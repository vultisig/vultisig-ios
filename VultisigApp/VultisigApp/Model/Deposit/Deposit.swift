//
//  Deposit.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 14/05/24.
//

import Foundation



// MARK: - SWAP
class TransactionMemoSwap {
    var asset: String
    var destinationAddress: String
    var limit: Double?
    var interval: Int?
    var quantity: Int?
    var affiliate: String?
    var fee: Double?
    
    init(asset: String, destinationAddress: String, limit: Double?, interval: Int?, quantity: Int?, affiliate: String?, fee: Double?) {
        self.asset = asset
        self.destinationAddress = destinationAddress
        self.limit = limit
        self.interval = interval
        self.quantity = quantity
        self.affiliate = affiliate
        self.fee = fee
    }
    
    func toString() -> String {
        var memo = "SWAP:\(self.asset):\(self.destinationAddress)"
        if let limit = self.limit {
            memo += ":\(limit)"
            if let interval = self.interval, let quantity = self.quantity {
                memo += "/\(interval)/\(quantity)"
            }
        }
        if let affiliate = self.affiliate, let fee = self.fee {
            memo += ":\(affiliate):\(fee)"
        }
        return memo
    }
}

// MARK: - DEPOSIT Savers
class TransactionMemoDepositSavers {
    var pool: String
    var affiliate: String?
    var fee: Double?
    
    init(pool: String, affiliate: String?, fee: Double?) {
        self.pool = pool
        self.affiliate = affiliate
        self.fee = fee
    }
    func toString() -> String {
        var memo = "DEPOSIT:\(self.pool)"
        if let affiliate = self.affiliate, let fee = self.fee {
            memo += ":\(affiliate):\(fee)"
        }
        return memo
    }
}

// MARK: - WITHDRAW Savers
class TransactionMemoWithdrawSavers {
    var pool: String
    var basisPoints: Int
    
    init(pool: String, basisPoints: Int) {
        self.pool = pool
        self.basisPoints = basisPoints
    }
    
    func toString() -> String {
        "WITHDRAW:\(self.pool):\(self.basisPoints)"
    }
}

// MARK: - OPEN Loan
class TransactionMemoOpenLoan {
    var asset: String
    var destinationAddress: String
    var minOut: Double
    var affiliate: String?
    var fee: Double?
    
    init(asset: String, destinationAddress: String, minOut: Double, affiliate: String?, fee: Double?) {
        self.asset = asset
        self.destinationAddress = destinationAddress
        self.minOut = minOut
        self.affiliate = affiliate
        self.fee = fee
    }
    
    func toString() -> String {
        var memo = "LOAN+:\(self.asset):\(self.destinationAddress):\(self.minOut)"
        if let affiliate = self.affiliate, let fee = self.fee {
            memo += ":\(affiliate):\(fee)"
        }
        return memo
    }
}

// MARK: - REPAY Loan
class TransactionMemoRepayLoan {
    var asset: String
    var destinationAddress: String
    var minOut: Double
    
    init(asset: String, destinationAddress: String, minOut: Double) {
        self.asset = asset
        self.destinationAddress = destinationAddress
        self.minOut = minOut
    }
    
    func toString() -> String {
        "LOAN-:\(self.asset):\(self.destinationAddress):\(self.minOut)"
    }
}

// MARK: - ADD Liquidity
class TransactionMemoAddLiquidity {
    var pool: String
    var pairedAddress: String?
    var affiliate: String?
    var fee: Double?
    
    init(pool: String, pairedAddress: String?, affiliate: String?, fee: Double?) {
        self.pool = pool
        self.pairedAddress = pairedAddress
        self.affiliate = affiliate
        self.fee = fee
    }
    
    func toString() -> String {
        var memo = "ADD:\(self.pool)"
        if let pairedAddress = self.pairedAddress {
            memo += ":\(pairedAddress)"
        }
        if let affiliate = self.affiliate, let fee = self.fee {
            memo += ":\(affiliate):\(fee)"
        }
        return memo
    }
}

// MARK: - WITHDRAW Liquidity
class TransactionMemoWithdrawLiquidity {
    var pool: String
    var basisPoints: Int
    var asset: String?
    
    init(pool: String, basisPoints: Int, asset: String?) {
        self.pool = pool
        self.basisPoints = basisPoints
        self.asset = asset
    }
    
    func toString() -> String {
        var memo = "WITHDRAW:\(self.pool):\(self.basisPoints)"
        if let assetString = self.asset {
            memo += ":\(assetString)"
        }
        return memo
    }
}

// MARK: - ADD Trade Account
class TransactionMemoAddTradeAccount {
    var address: String
    
    init(address: String) {
        self.address = address
    }
    func toString() -> String {
        "TRADE+:\(self.address)"
    }
}

// MARK: - WITHDRAW Trade Account
class TransactionMemoWithdrawTradeAccount {
    var address: String
    
    init(address: String) {
        self.address = address
    }
    
    func toString() -> String {
        "TRADE-:\(self.address)"
    }
}

// MARK: - BOND, UNBOND & LEAVE
class TransactionMemoNodeMaintenance {
    var nodeAddress: String
    var provider: String?
    var fee: Double?
    var amount: Double?
    var action: NodeAction
    
    enum NodeAction {
        case bond
        case unbond
        case leave
    }
    
    init(nodeAddress: String, provider: String?, fee: Double?, amount: Double?, action: NodeAction) {
        self.nodeAddress = nodeAddress
        self.provider = provider
        self.fee = fee
        self.amount = amount
        self.action = action
    }
    
    func toString() -> String {
        var memo = ""
        switch self.action {
        case .bond:
            memo = "BOND:\(self.nodeAddress)"
        case .unbond:
            memo = "UNBOND:\(self.nodeAddress):\(self.amount ?? 0)"
        case .leave:
            memo = "LEAVE:\(self.nodeAddress)"
        }
        if let provider = self.provider, let fee = self.fee {
            memo += ":\(provider):\(fee)"
        }
        return memo
    }
}

// MARK: - DONATE & RESERVE
class TransactionMemoDonateReserve {
    var pool: String?
    
    init(pool: String?) {
        self.pool = pool
    }
    
    func toString() -> String {
        guard let pool = self.pool else {
            return "RESERVE"
        }
        return "DONATE:\(pool)"
    }
}

// MARK: - MIGRATE
class TransactionMemoMigrate {
    var blockHeight: Int
    
    init(blockHeight: Int) {
        self.blockHeight = blockHeight
    }
    
    func toString() -> String {
        "MIGRATE:\(self.blockHeight)"
    }
}

// MARK: - NOOP
class NoOp {
    // This class represents a no-operation action, potentially for state fixes or maintenance.
}
