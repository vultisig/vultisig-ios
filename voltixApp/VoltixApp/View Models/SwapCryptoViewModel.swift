//
//  SwapCryptoViewModel.swift
//  VoltixApp
//
//  Created by Artur Guseinov on 02.04.2024.
//

import SwiftUI
import BigInt

@MainActor
class SwapCryptoViewModel: ObservableObject {

    private let titles = ["send", "verify", "pair", "keysign", "done"]

    @Published var coins: [Coin] = []
    @Published var currentIndex = 1
    @Published var currentTitle = "send"

    func load(tx: SwapTransaction, fromCoin: Coin, coins: [Coin]) {
        self.coins = coins.filter { $0.chain.isSwapSupported }
        tx.fromCoin = fromCoin
        tx.toCoin = coins.first!
    }

    // MARK: Progress

    var progress: Double {
        return Double(currentIndex) / Double(titles.count)
    }

    func validateForm(tx: SwapTransaction) -> Bool {
        return tx.fromCoin != tx.toCoin
            && tx.fromCoin != .example
            && tx.toCoin != .example
            && !tx.fromAmount.isEmpty
            && !tx.toAmount.isEmpty
    }

    func moveToNextView() {
        currentIndex += 1
        currentTitle = titles[currentIndex-1]
    }
}
