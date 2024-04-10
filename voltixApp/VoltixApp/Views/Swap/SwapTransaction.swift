//
//  SwapCryptoTransaction.swift
//  VoltixApp
//
//  Created by Artur Guseinov on 08.04.2024.
//

import Foundation

@MainActor
class SwapTransaction: ObservableObject {

    private let thorchainService = ThorchainService.shared
    private let balanceService = BalanceService.shared
    private let feeService = FeeService.shared

    @Published var fromCoin: Coin = .example {
        didSet {
            updateFromBalance()
            updateQuote()
            updateFee()
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

    @Published var toAmount: String = .empty
    @Published var gas: String = .empty

    @Published var fromBalance: String = .zero
    @Published var toBalance: String = .zero

    var quote: ThorchainSwapQuote?

    var feeString: String {
        return "\(gas) \(fromCoin.feeUnit)"
    }
}

private extension SwapTransaction {

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

    func updateFee() {
        Task { try await fetchFee() }
    }

    func fetchFee() async throws {
        let response = try await feeService.fetchFee(for: fromCoin)
        gas = response.gas
    }

    func fetchQuotes() async throws {
        guard let amount = Decimal(string: fromAmount), fromCoin != toCoin else {
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

        self.quote = quote
    }

    func fetchBalance(coin: Coin) async throws -> String {
        return try await balanceService.balance(for: coin).coinBalance
    }
}

