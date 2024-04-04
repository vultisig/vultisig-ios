//
//  SwapTransaction.swift
//  VoltixApp
//
//  Created by Artur Guseinov on 02.04.2024.
//

import Foundation
import SwiftUI

class SwapTransaction: ObservableObject {
    @Published var fromCoin: Coin = .example
    @Published var fromAmount: String = .empty
    @Published var toCoin: Coin = .example
    @Published var toAmount: String = .empty
    @Published var gas: String = .empty

    var fromBalance: String {
        return fromCoin.balanceString
    }

    var toBalance: String {
        return toCoin.balanceString
    }

    var feeString: String {
        return "\(gas) \(fromCoin.feeUnit)"
    }
}
