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

    private let thorchainService = ThorchainService.shared
    private let balanceService = BalanceService.shared

    private let titles = ["send", "verify", "pair", "keysign", "done"]

    @Published var fromCoin: Coin = .example {
        didSet {
            updateFromBalance()
            updateQuote()
        }
    }

    @Published var toCoin: Coin = .example {
        didSet {
            updateToBalance()
            updateQuote()
        }
    }

    @Published var fromAmount: String = .empty {
        didSet {
            updateQuote()
        }
    }

    @Published var coins: [Coin] = []
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
        self.coins = coins.filter { $0.chain.isSwapSupported }
        self.fromCoin = fromCoin
        self.toCoin = coins.first!
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

    enum Errors: Error {
        case swapQuoteParsingFailed
    }

    func updateFromBalance() {
        Task { fromBalance = try await fetchBalance(coin: fromCoin) }
    }

    func updateToBalance() {
        Task { toBalance = try await fetchBalance(coin: toCoin) }
    }

    func updateQuote() {
        Task { try await fetchQuotes() }
    }

    func fetchQuotes() async throws {
        guard let amount = Decimal(string: fromAmount), fromCoin.swapAsset != toCoin.swapAsset else {
            throw Errors.swapQuoteParsingFailed
        }

        let quote = try await thorchainService.fetchSwapQuotes(
            address: toCoin.address,
            fromAsset: fromCoin.swapAsset,
            toAsset: toCoin.swapAsset,
            amount: (amount * 100_000_000).description // https://dev.thorchain.org/swap-guide/quickstart-guide.html#admonition-info-2
        )

        guard let expected = Decimal(string: quote.expectedAmountOut) else {
            throw Errors.swapQuoteParsingFailed
        }

        toAmount = (expected / Decimal(100_000_000)).description
    }

    func fetchBalance(coin: Coin) async throws -> String {
        return try await balanceService.balance(for: coin).coinBalance
    }
}
