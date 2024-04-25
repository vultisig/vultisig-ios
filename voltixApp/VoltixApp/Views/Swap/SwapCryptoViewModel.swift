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

class SwapCryptoViewModel: ObservableObject, TransferViewModel {

    enum Flow {
        case normal
        case erc20

        var titles: [String] {
            switch self {
            case .normal:
                return ["send", "verify", "pair", "keysign", "done"]
            case .erc20:
                return ["send", "verifyApprove", "pair", "keysign", "verifySwap", "pair", "keysign", "done"]
            }
        }
    }

    private let thorchainService = ThorchainService.shared
    private let balanceService = BalanceService.shared
    private let blockchainService = BlockChainService.shared
    
    var quote: ThorchainSwapQuote?
    var keysignPayload: KeysignPayload?
    
    @MainActor @Published var coins: [Coin] = []
    @MainActor @Published var currentIndex = 1
    @MainActor @Published var currentTitle = "send"
    @MainActor @Published var hash: String?
    @MainActor @Published var flow: Flow = .normal

    @MainActor @Published var error: Error?
    @MainActor @Published var isLoading = false

    func load(tx: SwapTransaction, fromCoin: Coin, coins: [Coin]) async {
        self.coins = coins.filter { $0.chain.isSwapSupported }
        tx.toCoin = coins.first!
        tx.fromCoin = fromCoin

        updateInitial(tx: tx)
    }
    
    var progress: Double {
        return Double(currentIndex) / Double(flow.titles.count)
    }

    var spender: String {
        return quote?.router ?? .empty
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

    func gasString(tx: SwapTransaction) -> String {
        let fee = tx.fromCoin.fiat(for: tx.gas)
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
        currentTitle = flow.titles[currentIndex-1]
    }

    func buildSwapKeysignPayload(tx: SwapTransaction) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        
        do {
            guard let quote else {
                throw Errors.swapQuoteNotFound
            }

            guard quote.inboundAddress != nil || tx.fromCoin.chain == .thorChain else {
                throw Errors.swapQuoteInboundAddressNotFound
            }

            let toAddress = quote.router ?? quote.inboundAddress ?? tx.fromCoin.address
            let vaultAddress = quote.inboundAddress ?? tx.fromCoin.address
            let expirationTime = Date().addingTimeInterval(60 * 15) // 15 mins

            let swapPayload = THORChainSwapPayload(
                fromAddress: tx.fromCoin.address,
                fromAsset: swapAsset(for: tx.fromCoin),
                toAsset: swapAsset(for: tx.toCoin),
                toAddress: tx.toCoin.address,
                vaultAddress: vaultAddress,
                routerAddress: quote.router,
                fromAmount: String(swapAmount(for: tx.fromCoin, tx: tx)),
                toAmountLimit: "0", streamingInterval: "1", streamingQuantity: "0", 
                expirationTime: UInt64(expirationTime.timeIntervalSince1970)
            )

            let keysignFactory = KeysignPayloadFactory()

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

    func buildApproveKeysignPayload(tx: SwapTransaction) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        do {
            guard let quote else {
                throw Errors.swapQuoteNotFound
            }
            guard let router = quote.router else {
                throw Errors.swapQuoteRouterNotFound
            }
            let approvePayload = ERC20ApprovePayload(
                amount: .maxAllowance,
                spender: router
            )
            let chainSpecific = try await blockchainService.fetchSpecific(
                for: tx.fromCoin,
                action: .approve
            )
            keysignPayload = try await KeysignPayloadFactory().buildTransfer(
                coin: tx.fromCoin,
                toAddress: tx.fromCoin.contractAddress,
                amount: 0,
                memo: nil,
                chainSpecific: chainSpecific,
                swapPayload: nil,
                approvePayload: approvePayload
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


    func switchCoins(tx: SwapTransaction) {
        defer { clear(tx: tx) }

        let fromCoin = tx.fromCoin
        let toCoin = tx.toCoin

        tx.fromCoin = toCoin
        tx.toCoin = fromCoin

        Task {
            async let flow: () = updateFlow(tx: tx)
            async let fromBalance: () = updateFromBalance(tx: tx)
            async let toBalance: () = updateToBalance(tx: tx)
            async let quote: () = updateQuotes(tx: tx)
            async let fee: () = updateFee(tx: tx)

            _ = await [flow, quote, fromBalance, toBalance, fee]
        }
    }

    func updateInitial(tx: SwapTransaction) {
        Task {
            async let flow: () = updateFlow(tx: tx)
            async let fromBalance: () = updateFromBalance(tx: tx)
            async let toBalance: () = updateToBalance(tx: tx)
            async let fee: () = updateFee(tx: tx)

            _ = await [flow, fromBalance, toBalance, fee]
        }
    }

    func updateFromAmount(tx: SwapTransaction) {
        Task {
            await updateQuotes(tx: tx)
        }
    }

    func updateFromCoin(tx: SwapTransaction) {
        Task {
            async let flow: () = updateFlow(tx: tx)
            async let fromBalance: () = updateFromBalance(tx: tx)
            async let quote: () = updateQuotes(tx: tx)
            async let fee: () = updateFee(tx: tx)

            _ = await [flow, fromBalance, quote, fee]
        }
    }

    func updateToCoin(tx: SwapTransaction) {
        Task {
            async let toBalance: () = updateToBalance(tx: tx)
            async let quote: () = updateQuotes(tx: tx)

            _ = await [toBalance, quote]
        }
    }
}

private extension SwapCryptoViewModel {
    
    enum Errors: String, Error, LocalizedError {
        case swapQuoteParsingFailed
        case swapQuoteNotFound
        case swapQuoteInboundAddressNotFound
        case swapQuoteRouterNotFound

        var errorDescription: String? {
            return String(NSLocalizedString(rawValue, comment: ""))
        }
    }
}

private extension SwapCryptoViewModel {

    func updateFee(tx: SwapTransaction) async {
        do {
            let chainSpecific = try await blockchainService.fetchSpecific(for: tx.fromCoin)
            tx.gas = chainSpecific.gas
        } catch {
            self.error = error
        }
    }

    func updateFlow(tx: SwapTransaction) async {
        guard tx.fromCoin.chain.chainType == .EVM else {
            return flow = .normal
        }
        flow = tx.fromCoin.isNativeToken ? .normal : .erc20
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

            try await updateFlow(tx: tx, spender: spender)
        } catch {
            self.error = error
            clear(tx: tx)
        }
    }

    func updateFlow(tx: SwapTransaction, spender: String) async throws {
        guard tx.fromCoin.shouldApprove else {
            return flow = .normal
        }
        let service = try EvmServiceFactory.getService(forChain: tx.fromCoin)
        let allowance = try await service.fetchAllowance(
            contractAddress: tx.fromCoin.contractAddress,
            owner: tx.fromCoin.address,
            spender: spender
        )
        let amount = swapAmount(for: tx.fromCoin, tx: tx)
        flow = amount > allowance ? .erc20 : .normal
    }

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
    
    func swapAmount(for coin: Coin, tx: SwapTransaction) -> BigInt {
        switch coin.chain {
        case .thorChain, .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .dash:
            return BigInt(tx.amountInSats)
        case .mayaChain:
            return BigInt(tx.amountInCoinDecimal)
        case .ethereum, .avalanche,.arbitrum, .bscChain, .base, .optimism, .polygon, .blast, .cronosChain:
            if coin.isNativeToken {
                return BigInt(tx.amountInWei)
            } else {
                return BigInt(tx.amountInTokenWei)
            }
        case .gaiaChain, .kujira:
            return BigInt(tx.amountInCoinDecimal)
        case .solana:
            return BigInt(tx.amountInLamports)
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
