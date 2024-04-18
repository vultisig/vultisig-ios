//
//  THORBalanceExtension.swift
//  VoltixApp
//
//  Created by Johnny Luo on 22/3/2024.
//

import Foundation

extension [CosmosBalance] {
    func balance(denom: String) -> String {
        for balance in self {
            if balance.denom.lowercased() == denom {
                return balance.amount
            }
        }
        return .zero
    }
}
