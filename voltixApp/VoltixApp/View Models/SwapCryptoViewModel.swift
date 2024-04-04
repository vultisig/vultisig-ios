//
//  SwapCryptoViewModel.swift
//  VoltixApp
//
//  Created by Artur Guseinov on 02.04.2024.
//

import SwiftUI

@MainActor
class SwapCryptoViewModel: ObservableObject {

    private let thorchainService = ThorchainService.shared
    private let balanceService = BalanceService.shared

    private let titles = ["send", "verify", "pair", "keysign", "done"]

    @Published var fromCoin: Coin = .example {
        didSet {
            Task { fromBalance = try await fetchBalance(coin: fromCoin) }
        }
    }

    @Published var toCoin: Coin = .example {
        didSet {
            Task { toBalance = try await fetchBalance(coin: toCoin) }
        }
    }

    @Published var coins: [Coin] = []
    @Published var fromAmount: String = .empty
    @Published var toAmount: String = .empty
    @Published var fromBalance: String = .empty
    @Published var toBalance: String = .empty
    @Published var gas: String = .empty
    @Published var currentIndex = 1
    @Published var currentTitle = "send"

    var feeString: String {
        return "\(gas) \(fromCoin.feeUnit)"
    }

    func load(fromCoin: Coin, coins: [Coin]) async throws {
        self.coins = coins
        self.fromCoin = fromCoin
        self.toCoin = coins.first!

        let quote = try await thorchainService.fetchSwapQuotes(
            address: fromCoin.address,
            fromAsset: fromCoin.chain.thorAsset,
            toAsset: toCoin.chain.thorAsset,
            amount: fromAmount
        )
    }

    // MARK: Progress

    var progress: Double {
        return Double(currentIndex) / Double(titles.count)
    }

    func moveToNextView() {
        currentIndex += 1
        currentTitle = titles[currentIndex-1]
    }
}

private extension SwapCryptoViewModel {

    func fetchBalance(coin: Coin) async throws -> String {
        return try await balanceService.balance(for: coin).coinBalance
    }
}
