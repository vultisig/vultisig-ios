//
//  THORBalanceExtension.swift
//  VultisigApp
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

    func balance(denom: String, coin: CoinMeta) -> String {
        for balance in self {
            if coin.isNativeToken && balance.denom.lowercased() == denom {
                return balance.amount
            } else if !coin.isNativeToken && balance.denom.lowercased() == coin.contractAddress.lowercased() {
                return balance.amount
            }
        }
        return .zero
    }
}
