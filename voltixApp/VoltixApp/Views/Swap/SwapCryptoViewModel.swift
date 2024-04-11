//
//  SwapCryptoViewModel.swift
//  VoltixApp
//
//  Created by Artur Guseinov on 02.04.2024.
//

import SwiftUI
import BigInt
import WalletCore
import Mediator

@MainActor
class SwapCryptoViewModel: ObservableObject, TransferViewModel {

    private let thorchainService = ThorchainService.shared
    private let balanceService = BalanceService.shared
    private let feeService = FeeService.shared

    private let titles = ["send", "verify", "pair", "keysign", "done"]

    var quote: ThorchainSwapQuote?

    @Published var coins: [Coin] = []
    @Published var currentIndex = 1
    @Published var currentTitle = "send"
    @Published var hash: String?

    @Published var error: Error?

    var showError: Binding<Bool> {
        return Binding { self.error != nil } set: { _ in }
    }

    func load(tx: SwapTransaction, fromCoin: Coin, coins: [Coin]) async {
        self.coins = coins.filter { $0.chain.isSwapSupported }
        tx.toCoin = coins.first!
        tx.fromCoin = fromCoin

        await updateFromBalance(tx: tx)
        await updateToBalance(tx: tx)
        await updateFee(tx: tx)
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
            && quote != nil
    }

    func moveToNextView() {
        currentIndex += 1
        currentTitle = titles[currentIndex-1]
    }

    func buildKeysignPayload(tx: SwapTransaction) -> KeysignPayload {
        let swapPayload = THORChainSwapPayload(
            fromAddress: tx.fromCoin.address,
            fromAsset: swapAsset(for: tx.fromCoin),
            toAsset: swapAsset(for: tx.toCoin),
            toAddress: tx.toCoin.address,
            vaultAddress: quote!.inboundAddress,
            routerAddress: nil,
            fromAmount: tx.fromAmount,
            toAmountLimit: .zero
        )
        return KeysignPayloadFactory().buildSwap(coin: tx.fromCoin, swapPayload: swapPayload)
    }

    func stopMediator() {
        Mediator.shared.stop()
    }

    func updateFromBalance(tx: SwapTransaction) async {
        do {
            tx.fromBalance = try await fetchBalance(coin: tx.fromCoin)
        } catch {
            self.error = error
        }
    }

    func updateToBalance(tx: SwapTransaction) async {
        do {
            tx.toBalance = try await fetchBalance(coin: tx.toCoin)
        } catch {
            self.error = error
        }
    }

    func updateFee(tx: SwapTransaction) async {
        do {
            let response = try await feeService.fetchFee(for: tx.fromCoin)
            tx.gas = response.gas
        } catch {
            self.error = error
        }
    }

    func updateQuotes(tx: SwapTransaction) async {
        do {
            guard let amount = Decimal(string: tx.fromAmount), tx.fromCoin != tx.toCoin else {
                throw Errors.swapQuoteParsingFailed
            }

            let quote = try await thorchainService.fetchSwapQuotes(
                address: tx.toCoin.address,
                fromAsset: tx.fromCoin.swapAsset,
                toAsset: tx.toCoin.swapAsset,
                amount: (amount * 100_000_000).description // https://dev.thorchain.org/swap-guide/quickstart-guide.html#admonition-info-2
            )

            guard let expected = Decimal(string: quote.expectedAmountOut) else {
                throw Errors.swapQuoteParsingFailed
            }

            tx.toAmount = (expected / Decimal(100_000_000)).description

            self.quote = quote
        } catch {
            self.quote = nil
            print("Swap quote error: \(error.localizedDescription)")
        }
    }
}

private extension SwapCryptoViewModel {

    enum Errors: String, Error, LocalizedError {
        case swapQuoteParsingFailed

        var errorDescription: String? {
            return String(NSLocalizedString(rawValue, comment: ""))
        }
    }

    func fetchBalance(coin: Coin) async throws -> String {
        return try await balanceService.balance(for: coin).coinBalance
    }
}

private extension SwapCryptoViewModel {

    func swapAsset(for coin: Coin) -> THORChainSwapAsset {
        return THORChainSwapAsset.with {
            switch coin.chain {
            case .thorChain:
                $0.chain = .thor
            case .ethereum:
                $0.chain = .eth
            case .avalanche:
                $0.chain = .avax
            case .bscChain:
                $0.chain = .bsc
            case .bitcoin:
                $0.chain = .btc
            case .bitcoinCash:
                $0.chain = .bch
            case .litecoin:
                $0.chain = .ltc
            case .dogecoin:
                $0.chain = .doge
            case .gaiaChain:
                $0.chain = .atom
            case .solana: break
            }
            $0.symbol = coin.ticker
            if !coin.isNativeToken {
                $0.tokenID = coin.contractAddress
            }
        }
    }
}
