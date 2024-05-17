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
