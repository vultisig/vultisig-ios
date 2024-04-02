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
    @Published var fromBalance: String = .empty
    @Published var fromAmount: String = .empty
    @Published var toCoin: Coin = .example
    @Published var toBalance: String = .empty
    @Published var toAmount: String = .empty
    @Published var gas: String = .empty
}
