//
//  SwapCryptoViewModel.swift
//  VultisigApp
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

    private let swapService = SwapService.shared
    private let blockchainService = BlockChainService.shared
    private let balanceService = BalanceService.shared

    var keysignPayload: KeysignPayload?
    
    @MainActor @Published var coins: [Coin] = []
    @MainActor @Published var currentIndex = 1
    @MainActor @Published var currentTitle = "send"
    @MainActor @Published var hash: String?
    @MainActor @Published var flow: Flow = .normal

    @MainActor @Published var error: Error?
    @MainActor @Published var isLoading = false
    @MainActor @Published var quoteLoading = false

    func load(tx: SwapTransaction, fromCoin: Coin, coins: [Coin], vault: Vault) async {
        self.coins = coins.filter { $0.chain.isSwapSupported }
        tx.toCoin = coins.first!
        tx.fromCoin = fromCoin

        updateInitial(tx: tx, vault: vault)
    }
    
    var progress: Double {
        return Double(currentIndex) / Double(flow.titles.count)
    }

    func explorerLink(tx: SwapTransaction, hash: String) -> String {
        return Endpoint.getExplorerURL(chainTicker: tx.fromCoin.chain.ticker, txid: hash)
    }

    func progressLink(tx: SwapTransaction, hash: String) -> String? {
        switch tx.quote {
        case .thorchain:
            return Endpoint.getSwapProgressURL(txid: hash)
        case .oneinch, .none:
            return nil
        }
    }

    func showFees(tx: SwapTransaction) -> Bool {
        let fee = swapFeeString(tx: tx)
        return !fee.isEmpty && !fee.isZero
    }
    
    func showDuration(tx: SwapTransaction) -> Bool {
        return showFees(tx: tx)
    }
    
    func showToAmount(tx: SwapTransaction) -> Bool {
        return tx.toAmountDecimal != 0
    }
    
    func swapFeeString(tx: SwapTransaction) -> String {
        guard let inboundFeeDecimal = tx.inboundFeeDecimal else { return .empty }

        let fromCoin = feeCoin(tx: tx)
        let inboundFee = tx.toCoin.raw(for: inboundFeeDecimal)
        let fee = tx.toCoin.fiat(for: inboundFee) + fromCoin.fiat(for: tx.gas)
        return fee.formatToFiat(includeCurrencySymbol: true)
    }

    func approveFeeString(tx: SwapTransaction) -> String {
        let fromCoin = feeCoin(tx: tx)
        let fee = fromCoin.fiat(for: tx.gas)
        return fee.formatToFiat(includeCurrencySymbol: true)
    }

    func isSufficientBalance(tx: SwapTransaction) -> Bool {
        let feeCoin = feeCoin(tx: tx)
        let fromFee = feeCoin.decimal(for: tx.gas)

        let fromBalance = tx.fromCoin.balanceDecimal
        let feeCoinBalance = feeCoin.balanceDecimal

        let amount = Decimal(string: tx.fromAmount) ?? 0

        if feeCoin == tx.fromCoin {
            return fromFee + amount <= fromBalance
        } else {
            return fromFee <= feeCoinBalance && amount <= fromBalance
        }
    }

    func durationString(tx: SwapTransaction) -> String {
        guard let duration = tx.quote?.totalSwapSeconds else { return "Instant" }
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
            && !tx.toAmountDecimal.isZero
            && tx.quote != nil
            && isSufficientBalance(tx: tx)
            && !quoteLoading
    }
    
    func moveToNextView() {
        currentIndex += 1
        currentTitle = flow.titles[currentIndex-1]
    }

    func buildSwapKeysignPayload(tx: SwapTransaction, vault: Vault) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        
        do {
            guard let quote = tx.quote else {
                throw Errors.unexpectedError
            }

            let chainSpecific = try await blockchainService.fetchSpecific(
                for: tx.fromCoin,
                action: .swap,
                sendMaxAmount: false
            )

            switch quote {
            case .thorchain(let quote):

                guard quote.inboundAddress != nil || tx.fromCoin.chain == .thorChain else {
                    throw Errors.unexpectedError
                }

                let toAddress = quote.router ?? quote.inboundAddress ?? tx.fromCoin.address
                let vaultAddress = quote.inboundAddress ?? tx.fromCoin.address
                let expirationTime = Date().addingTimeInterval(60 * 15) // 15 mins
                let keysignFactory = KeysignPayloadFactory()

                let swapPayload = THORChainSwapPayload(
                    fromAddress: tx.fromCoin.address,
                    fromCoin: tx.fromCoin,
                    toCoin: tx.toCoin,
                    vaultAddress: vaultAddress,
                    routerAddress: quote.router,
                    fromAmount: swapFromAmount(tx: tx),
                    toAmountDecimal: tx.toAmountDecimal,
                    toAmountLimit: "0", streamingInterval: "1", streamingQuantity: "0",
                    expirationTime: UInt64(expirationTime.timeIntervalSince1970)
                )
                keysignPayload = try await keysignFactory.buildTransfer(
                    coin: tx.fromCoin,
                    toAddress: toAddress,
                    amount: tx.amountInCoinDecimal,
                    memo: nil,
                    chainSpecific: chainSpecific,
                    swapPayload: .thorchain(swapPayload),
                    vault: vault
                )

                return true

            case .oneinch(let quote):
                let keysignFactory = KeysignPayloadFactory()
                let payload = OneInchSwapPayload(
                    fromCoin: tx.fromCoin,
                    toCoin: tx.toCoin,
                    fromAmount: swapFromAmount(tx: tx),
                    toAmountDecimal: tx.toAmountDecimal,
                    quote: quote
                )
                keysignPayload = try await keysignFactory.buildTransfer(
                    coin: tx.fromCoin,
                    toAddress: quote.tx.to,
                    amount: tx.amountInCoinDecimal,
                    memo: nil,
                    chainSpecific: chainSpecific,
                    swapPayload: .oneInch(payload),
                    vault: vault
                )

                return true
            }
        }
        catch {
            self.error = error
            return false
        }
    }

    func buildApproveKeysignPayload(tx: SwapTransaction, vault: Vault) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        do {
            guard let quote = tx.quote, let router = quote.router else {
                throw Errors.unexpectedError
            }
            let approvePayload = ERC20ApprovePayload(
                amount: .maxAllowance,
                spender: router
            )
            let chainSpecific = try await blockchainService.fetchSpecific(
                for: tx.fromCoin, sendMaxAmount: false
            )
            keysignPayload = try await KeysignPayloadFactory().buildTransfer(
                coin: tx.fromCoin,
                toAddress: tx.fromCoin.contractAddress,
                amount: 0,
                memo: nil,
                chainSpecific: chainSpecific,
                swapPayload: nil,
                approvePayload: approvePayload,
                vault: vault
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


    func switchCoins(tx: SwapTransaction, vault: Vault) {
        defer { clear(tx: tx) }

        let fromCoin = tx.fromCoin
        let toCoin = tx.toCoin

        tx.fromCoin = toCoin
        tx.toCoin = fromCoin

        Task {
            async let quote: () = updateQuotes(tx: tx)
            async let fee: () = updateFee(tx: tx, vault: vault)

            _ = await [quote, fee]
        }
    }

    func updateInitial(tx: SwapTransaction, vault: Vault) {
        Task {
            await updateFee(tx: tx, vault: vault)
        }
    }

    func updateFromAmount(tx: SwapTransaction) {
        Task {
            await updateQuotes(tx: tx)
        }
    }

    func updateFromCoin(tx: SwapTransaction, vault: Vault) {
        Task {
            async let quote: () = updateQuotes(tx: tx)
            async let fee: () = updateFee(tx: tx, vault: vault)

            _ = await [quote, fee]
        }
    }

    func updateToCoin(tx: SwapTransaction) {
        Task {
            await updateQuotes(tx: tx)
        }
    }
    
    func handleBackTap() {
        currentIndex-=1
    }
}

private extension SwapCryptoViewModel {

    enum Errors: String, Error, LocalizedError {
        case unexpectedError
        case insufficientFunds
        case swapAmountTooSmall

        var errorDescription: String? {
            switch self {
            case .unexpectedError:
                return "Unexpected swap error"
            case .insufficientFunds:
                return "Insufficient funds"
            case .swapAmountTooSmall:
                return "Swap amount too small"
            }
        }
    }

    func updateFee(tx: SwapTransaction, vault: Vault) async {
        do {
            switch tx.quote {
            case .thorchain, .none:
                let chainSpecific = try await blockchainService.fetchSpecific(for: tx.fromCoin, action: .swap, sendMaxAmount: false)
                tx.gas = try await thorchainFee(for: chainSpecific, tx: tx, vault: vault)
            case .oneinch(let quote):
                tx.gas = oneInchFee(quote: quote)
            }
        } catch {
            self.error = error
        }
    }

    func updateQuotes(tx: SwapTransaction) async {
        quoteLoading = true
        defer { quoteLoading = false }

        guard !tx.fromAmount.isEmpty else { return clear(tx: tx) }

        error = nil

        do {
            guard let amount = Decimal(string: tx.fromAmount), !amount.isZero, tx.fromCoin != tx.toCoin else {
                return
            }

            let quote = try await swapService.fetchQuote(amount: amount, fromCoin: tx.fromCoin, toCoin: tx.toCoin)

            if !isSufficientBalance(tx: tx) {
                throw Errors.insufficientFunds
            }

            tx.quote = quote

            if case SwapQuote.oneinch(let quote) = quote {
                tx.gas = oneInchFee(quote: quote)
            }

            try await updateFlow(tx: tx)
        } catch {
            self.error = error
            clear(tx: tx)
        }
    }

    func updateFlow(tx: SwapTransaction) async throws {
        guard tx.fromCoin.shouldApprove, let spender = tx.router else {
            return flow = .normal
        }
        let service = try EvmServiceFactory.getService(forChain: tx.fromCoin)
        let allowance = try await service.fetchAllowance(
            contractAddress: tx.fromCoin.contractAddress,
            owner: tx.fromCoin.address,
            spender: spender
        )
        flow = swapFromAmount(tx: tx) > allowance ? .erc20 : .normal
    }

    func clear(tx: SwapTransaction) {
        tx.quote = nil
    }
    
    func swapFromAmount(tx: SwapTransaction) -> BigInt {
        return BigInt(tx.amountInCoinDecimal)
    }

    func feeCoin(tx: SwapTransaction) -> Coin {
        switch tx.fromCoin.chainType {
        case .UTXO, .Solana, .THORChain, .Cosmos, .Polkadot, .Sui:
            return tx.fromCoin
        case .EVM:
            guard !tx.fromCoin.isNativeToken else { return tx.fromCoin }
            return coins.first(where: { $0.chain == tx.fromCoin.chain && $0.isNativeToken }) ?? tx.fromCoin
        }
    }

    func thorchainFee(for chainSpecific: BlockChainSpecific, tx: SwapTransaction, vault: Vault) async throws -> BigInt {
        switch chainSpecific {
        case .Ethereum(let maxFeePerGas, let priorityFee, _, let gasLimit):
            return (maxFeePerGas + priorityFee) * gasLimit
        case .UTXO:
            let keysignFactory = KeysignPayloadFactory()

            let keysignPayload = try await keysignFactory.buildTransfer(
                coin: tx.fromCoin,
                toAddress: tx.fromCoin.address,
                amount: tx.amountInCoinDecimal,
                memo: nil,
                chainSpecific: chainSpecific,
                swapPayload: nil,
                vault: vault
            )

            let utxo = UTXOChainsHelper(
                coin: tx.fromCoin.coinType,
                vaultHexPublicKey: vault.pubKeyECDSA,
                vaultHexChainCode: vault.hexChainCode
            )

            let result = utxo.getBitcoinTransactionPlan(keysignPayload: keysignPayload)

            switch result {
            case .success(let plan):
                return BigInt(plan.fee)
            case .failure(let error):
                throw error
            }

        case .Cosmos, .THORChain, .Polkadot, .MayaChain, .Solana, .Sui:
            return chainSpecific.gas
        }
    }

    func oneInchFee(quote: OneInchQuote) -> BigInt {
        let gasPrice = BigInt(quote.tx.gasPrice) ?? BigInt.zero
        return gasPrice * BigInt(EVMHelper.defaultETHSwapGasUnit)
    }
}
