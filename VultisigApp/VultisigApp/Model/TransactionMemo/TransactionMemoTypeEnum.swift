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
    case bond,
         unbond,
         leave
    
    var id: String { self.rawValue }
}


enum TransactionMemoExpertType: String, CaseIterable, Identifiable {
    case bond,
         unbond,
         leave,
         swap,
         depositSavers,
         withdrawSavers,
         openLoan,
         repayLoan,
         addLiquidity,
         withdrawLiquidity,
         addTradeAccount,
         withdrawTradeAccount,
         donateReserve,
         migrate
    
    var id: String { self.rawValue }
}

extension TransactionMemoType: CustomStringConvertible {
    var description: String {
        self.rawValue
    }
}

extension TransactionMemoExpertType: CustomStringConvertible {
    var description: String {
        self.rawValue
    }
}
