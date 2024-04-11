//
//  SwapCryptoTransaction.swift
//  VoltixApp
//
//  Created by Artur Guseinov on 08.04.2024.
//

import Foundation

@MainActor
class SwapTransaction: ObservableObject {

    @Published var fromCoin: Coin = .example
    @Published var toCoin: Coin = .example
    @Published var fromAmount: String = .empty
    @Published var toAmount: String = .empty
    @Published var gas: String = .empty

    @Published var fromBalance: String = .zero
    @Published var toBalance: String = .zero

    var feeString: String {
        return "\(gas) \(fromCoin.feeUnit)"
    }
}
