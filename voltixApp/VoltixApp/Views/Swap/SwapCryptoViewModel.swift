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
    
    func load(tx: SwapTransaction, fromCoin: Coin, coins: [Coin]) async {
        self.coins = coins.filter { $0.chain.isSwapSupported }
        tx.toCoin = coins.first!
        tx.fromCoin = fromCoin
        
        await updateFromBalance(tx: tx)
        await updateToBalance(tx: tx)
        await updateFee(tx: tx)
    }
    
    var progress: Double {
        return Double(currentIndex) / Double(titles.count)
    }
    
    func showFees(tx: SwapTransaction) -> Bool {
        return tx.inboundFee != .zero
    }
    
    func showDuration(tx: SwapTransaction) -> Bool {
        return tx.duration != .zero
    }
    
    func showToAmount(tx: SwapTransaction) -> Bool {
        return tx.toAmount != .empty
    }
    
    func feeString(tx: SwapTransaction) -> String {
        guard !tx.inboundFee.isZero else { return .empty }
        guard !tx.gas.isZero else { return .empty }

        let fee = tx.toCoin.fiat(for: tx.inboundFee) + tx.fromCoin.fiat(for: tx.gas)
        return fee.formatToFiat(includeCurrencySymbol: true)
    }

    func isSufficientBalance(tx: SwapTransaction) -> Bool {
        let fromFee = tx.fromCoin.decimal(for: tx.gas)
        let toFee = tx.toCoin.decimal(for: tx.inboundFee)
        let fromBalance = Decimal(string: tx.fromBalance) ?? -1
        let toBalance = Decimal(string: tx.toBalance) ?? -1
        let amount = Decimal(string: tx.fromAmount) ?? 0
        return fromFee + amount <= fromBalance && toFee <= toBalance
    }

    func durationString(tx: SwapTransaction) -> String {
        guard let duration = quote?.totalSwapSeconds else { return .empty }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.includesApproximationPhrase = false
        formatter.includesTimeRemainingPhrase = false
        formatter.allowedUnits = [.day, .hour, .minute, .second]
        formatter.maximumUnitCount = 1
        let fromDate = Date(timeIntervalSince1970: 0)
        let toDate = Date(timeIntervalSince1970: TimeInterval(duration))
        return formatter.string(from: fromDate, to: toDate) ?? .empty
    }
    
    func validateForm(tx: SwapTransaction) -> Bool {
        return tx.fromCoin != tx.toCoin
        && tx.fromCoin != .example
        && tx.toCoin != .example
        && !tx.fromAmount.isEmpty
        && !tx.toAmount.isEmpty
        && quote != nil
        && isSufficientBalance(tx: tx)
    }
    
    func moveToNextView() {
        currentIndex += 1
        currentTitle = titles[currentIndex-1]
    }
    
    func buildKeysignPayload(tx: SwapTransaction) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        
        do {
            guard let quote else {
                throw Errors.swapQuoteNotFound
            }

            guard quote.inboundAddress != nil || tx.fromCoin.chain == .thorChain else {
                throw Errors.swapQuoteInboundAddressNotFound
            }

            let toAddress = quote.inboundAddress ?? tx.fromCoin.address

            let swapPayload = THORChainSwapPayload(
                fromAddress: tx.fromCoin.address,
                fromAsset: swapAsset(for: tx.fromCoin),
                toAsset: swapAsset(for: tx.toCoin),
                toAddress: tx.toCoin.address,
                vaultAddress: toAddress,
                routerAddress: quote.router,
                fromAmount: swapAmount(for: tx.fromCoin, tx: tx),
                toAmountLimit: "0", streamingInterval: "1", streamingQuantity: "0"
            )

            let keysignFactory = KeysignPayloadFactory()

            // TODO: Cache chain specific?
            let chainSpecific = try await blockchainService.fetchSpecific(for: tx.fromCoin)
            
            keysignPayload = try await keysignFactory.buildTransfer(
                coin: tx.fromCoin,
                toAddress: toAddress,
                amount: BigInt(amount(for: tx.fromCoin, tx: tx)),
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

    func updateFee(tx: SwapTransaction) async {
        do {
            let chainSpecific = try await blockchainService.fetchSpecific(for: tx.fromCoin)
            tx.gas = chainSpecific.gas
        } catch {
            self.error = error
        }
    }

    func updateFromBalance(tx: SwapTransaction) async {
        do {
            tx.fromBalance = try await balanceService.balance(for: tx.fromCoin).coinBalance
        } catch {
            self.error = error
        }
    }
    
    func updateToBalance(tx: SwapTransaction) async {
        do {
            tx.toBalance = try await balanceService.balance(for: tx.toCoin).coinBalance
        } catch {
            self.error = error
        }
    }
    
    func updateQuotes(tx: SwapTransaction) async {
        guard !tx.fromAmount.isEmpty else { return clear(tx: tx) }

        do {
            guard let amount = Decimal(string: tx.fromAmount), tx.fromCoin != tx.toCoin else {
                throw Errors.swapQuoteParsingFailed
            }

            let quote = try await thorchainService.fetchSwapQuotes(
                address: tx.toCoin.address,
                fromAsset: tx.fromCoin.swapAsset,
                toAsset: tx.toCoin.swapAsset,
                amount: (amount * 100_000_000).description, // https://dev.thorchain.org/swap-guide/quickstart-guide.html#admonition-info-2
                interval: "1"
            )

            guard let expected = Decimal(string: quote.expectedAmountOut) else {
                throw Errors.swapQuoteParsingFailed
            }

            guard let fees = Decimal(string: quote.fees.total) else {
                throw Errors.swapQuoteParsingFailed
            }

            let toDecimals = Int(tx.toCoin.decimals) ?? 0
            let inboundFeeDecimal = fees * pow(10, max(0, toDecimals - 8))

            tx.toAmount = (expected / Decimal(100_000_000)).description
            tx.inboundFee = BigInt(stringLiteral: inboundFeeDecimal.description)
            tx.duration = quote.totalSwapSeconds ?? 0

            self.quote = quote
        } catch {
            self.error = error
            clear(tx: tx)
        }
    }
}

private extension SwapCryptoViewModel {
    
    enum Errors: String, Error, LocalizedError {
        case swapQuoteParsingFailed
        case swapQuoteNotFound
        case swapQuoteInboundAddressNotFound

        var errorDescription: String? {
            return String(NSLocalizedString(rawValue, comment: ""))
        }
    }
}

private extension SwapCryptoViewModel {
    
    func clear(tx: SwapTransaction) {
        quote = nil
        tx.toAmount = .empty
        tx.inboundFee = .zero
        tx.duration = .zero
    }
    
    func amount(for coin: Coin, tx: SwapTransaction) -> Int64 {
        switch coin.chain {
        case .thorChain:
            return tx.amountInSats
        case .mayaChain:
            return tx.amountInCoinDecimal
        case .ethereum, .avalanche,.arbitrum, .bscChain, .base, .optimism, .polygon, .blast, .cronosChain:
            if coin.isNativeToken {
                return Int64(tx.amountInWei)
            } else {
                return Int64(tx.amountInTokenWei)
            }
        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .dash:
            return tx.amountInSats
        case .gaiaChain, .kujira:
            return tx.amountInCoinDecimal
        case .solana:
            return tx.amountInLamports
        }
    }
    
    func swapAmount(for coin: Coin, tx: SwapTransaction) -> String {
        switch coin.chain {
        case .thorChain, .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .dash:
            return String(tx.amountInSats)
        case .mayaChain:
            return String(tx.amountInCoinDecimal)
        case .ethereum, .avalanche,.arbitrum, .bscChain, .base, .optimism, .polygon, .blast, .cronosChain:
            if coin.isNativeToken {
                return String(tx.amountInWei)
            } else {
                return String(tx.amountInTokenWei)
            }
        case .gaiaChain, .kujira:
            return String(tx.amountInCoinDecimal)
        case .solana:
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
            case .solana, .dash, .kujira, .mayaChain, .arbitrum, .base, .optimism, .polygon, .blast, .cronosChain: break
            }
            $0.symbol = coin.ticker
            if !coin.isNativeToken {
                $0.tokenID = coin.contractAddress
            }
        }
    }
}
