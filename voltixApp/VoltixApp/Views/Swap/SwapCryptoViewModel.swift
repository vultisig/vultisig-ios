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
    private let blockchainService = BlockChainService.shared

    private let titles = ["send", "verify", "pair", "keysign", "done"]

    var quote: ThorchainSwapQuote?
    var keysignPayload: KeysignPayload?

    @Published var coins: [Coin] = []
    @Published var currentIndex = 1
    @Published var currentTitle = "send"
    @Published var hash: String?

    @Published var error: Error?
    @Published var isLoading = false

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

    func buildKeysignPayload(tx: SwapTransaction) async -> Bool {
        isLoading = true
        defer { isLoading = false }

        let toAddress = quote!.inboundAddress

        let swapPayload = THORChainSwapPayload(
            fromAddress: tx.fromCoin.address,
            fromAsset: swapAsset(for: tx.fromCoin),
            toAsset: swapAsset(for: tx.toCoin),
            toAddress: tx.toCoin.address,
            vaultAddress: quote!.inboundAddress,
            routerAddress: quote!.router,
            fromAmount: swapAmount(for: tx.fromCoin, tx: tx),
            toAmountLimit: quote?.expectedAmountOut ?? .zero
        )
        
        let keysignFactory = KeysignPayloadFactory()

        do {
            // TODO: Cache chain specific?
            let chainSpecific = try await blockchainService.fetchSpecific(for: tx.fromCoin)

            keysignPayload = try await keysignFactory.buildTransfer(
                coin: tx.fromCoin,
                toAddress: toAddress,
                amount: amount(for: tx.fromCoin, tx: tx),
                memo: nil,
                chainSpecific: chainSpecific,
                swapPayload: swapPayload
            )

            return true
        }
        catch {
            self.error = error
            return false
        }
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
            let chainSpecific = try await blockchainService.fetchSpecific(for: tx.fromCoin)
            tx.gas = chainSpecific.gas
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

    func amount(for coin: Coin, tx: SwapTransaction) -> Int64 {
        switch coin.chain {
        case .thorChain:
            return tx.amountInSats
        case .ethereum, .avalanche, .bscChain:
            if coin.isNativeToken {
                return tx.amountInGwei
            } else {
                return tx.amountInTokenWeiInt64
            }
        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin:
            return tx.amountInSats
        case .gaiaChain:
            return tx.amountInCoinDecimal
        case .solana, .ton:
            return tx.amountInLamports
        }
    }

    func swapAmount(for coin: Coin, tx: SwapTransaction) -> String {
        switch coin.chain {
        case .thorChain, .bitcoin, .bitcoinCash, .litecoin, .dogecoin:
            return String(tx.amountInSats)
        case .ethereum, .avalanche, .bscChain:
            if coin.isNativeToken {
                return String(tx.amountInWei)
            } else {
                return String(tx.amountInTokenWeiInt64)
            }
        case .gaiaChain:
            return String(tx.amountInCoinDecimal)
        case .solana, .ton:
            return String(tx.amountInLamports)
        }
    }

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
            case .solana, .ton: break
            }
            $0.symbol = coin.ticker
            if !coin.isNativeToken {
                $0.tokenID = coin.contractAddress
            }
        }
    }
}
