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
    private let titles = ["send", "verify", "pair", "keysign", "done"]

    private let swapService = SwapService.shared
    private let blockchainService = BlockChainService.shared
    private let fastVaultService = FastVaultService.shared
    private let balanceService = BalanceService.shared
    private let rateProvider = RateProvider.shared

    private var updateQuoteTask: Task<Void, Never>?
    private var updateFeesTask: Task<Void, Never>?

    var keysignPayload: KeysignPayload?
    
    @MainActor @Published var currentIndex = 1
    @MainActor @Published var currentTitle = "send"
    @MainActor @Published var hash: String?
    @MainActor @Published var approveHash: String?

    @MainActor @Published var error: Error?
    @MainActor @Published var isLoading = false
    @MainActor @Published var quoteLoading = false
    @MainActor @Published var dataLoaded = false

    var progress: Double {
        return Double(currentIndex) / Double(titles.count)
    }

    func load(initialFromCoin: Coin?, initialToCoin: Coin?, vault: Vault, tx: SwapTransaction) {
        let allCoins = vault.coins

        guard !dataLoaded, !allCoins.isEmpty else { return }

        let (fromCoins, fromCoin) = SwapCoinsResolver.resolveFromCoins(
            allCoins: allCoins
        )

        let resolvedFromCoin = initialFromCoin ?? fromCoin

        let (toCoins, toCoin) = SwapCoinsResolver.resolveToCoins(
            fromCoin: resolvedFromCoin,
            allCoins: allCoins,
            selectedToCoin: initialToCoin ?? .example
        )

        tx.load(fromCoin: resolvedFromCoin, toCoin: toCoin, fromCoins: fromCoins, toCoins: toCoins)

        dataLoaded = true
    }

    func loadFastVault(tx: SwapTransaction, vault: Vault) async {
        tx.isFastVault = await fastVaultService.exist(pubKeyECDSA: vault.pubKeyECDSA)
    }

    func updateCoinLists(tx: SwapTransaction) {
        let (toCoins, toCoin) = SwapCoinsResolver.resolveToCoins(
            fromCoin: tx.fromCoin,
            allCoins: tx.fromCoins,
            selectedToCoin: tx.toCoin
        )
        tx.toCoin = toCoin
        tx.toCoins = toCoins
    }

    func progressLink(tx: SwapTransaction, hash: String) -> String? {
        switch tx.quote {
        case .thorchain:
            return Endpoint.getSwapProgressURL(txid: hash)
        case .mayachain:
            return Endpoint.getMayaSwapTracker(txid: hash)
        case .oneinch, .lifi, .none:
            return nil
        }
    }
    
    func fromFiatAmount(tx: SwapTransaction) -> String {
        return tx.fromCoin.fiat(decimal: tx.fromAmountDecimal).description
    }
    
    func toFiatAmount(tx: SwapTransaction) -> String {
        return tx.toCoin.fiat(decimal: tx.toAmountDecimal).description
    }
    
    func showGas(tx: SwapTransaction) -> Bool {
        return !tx.gas.isZero
    }
    
    func showFees(tx: SwapTransaction) -> Bool {
        let fee = swapFeeString(tx: tx)
        return !fee.isEmpty && !fee.isZero
    }
    
    func showDuration(tx: SwapTransaction) -> Bool {
        return showFees(tx: tx)
    }

    func showAllowance(tx: SwapTransaction) -> Bool {
        return tx.isApproveRequired
    }

    func showToAmount(tx: SwapTransaction) -> Bool {
        return tx.toAmountDecimal != 0
    }
    
    func swapFeeString(tx: SwapTransaction) -> String {
        guard let inboundFeeDecimal = tx.inboundFeeDecimal else { return .empty }
        
        let fromCoin = feeCoin(tx: tx)
        let inboundFee = tx.toCoin.raw(for: inboundFeeDecimal)
        let fee = tx.toCoin.fiat(value: inboundFee) + fromCoin.fiat(value: tx.fee)
        return fee.formatToFiat(includeCurrencySymbol: true)
    }
    
    func swapGasString(tx: SwapTransaction) -> String {
        let coin = feeCoin(tx: tx)
        
        let decimals = coin.decimals
        
        if coin.chain.chainType == .EVM {
            guard let weiPerGWeiDecimal = Decimal(string: EVMHelper.weiPerGWei.description) else {
                return .empty
            }
            return "\(Decimal(tx.gas) / weiPerGWeiDecimal) \(coin.chain.feeUnit)"
        } else {
            return "\((Decimal(tx.gas) / pow(10 ,decimals)).formatToDecimal(digits: decimals).description) \(coin.chain.feeUnit)"
        }
    }
    
    func approveFeeString(tx: SwapTransaction) -> String {
        let fromCoin = feeCoin(tx: tx)
        let fee = fromCoin.fiat(value: tx.fee)
        return fee.formatToFiat(includeCurrencySymbol: true)
    }
    
    func isSufficientBalance(tx: SwapTransaction) -> Bool {
        let feeCoin = feeCoin(tx: tx)
        let fromFee = feeCoin.decimal(for: tx.fee)
        
        let fromBalance = tx.fromCoin.balanceDecimal
        let feeCoinBalance = feeCoin.balanceDecimal
        
        let amount = Decimal(string: tx.fromAmount) ?? 0
        
        if feeCoin == tx.fromCoin {
            return fromFee + amount <= fromBalance
        } else {
            return fromFee <= feeCoinBalance && amount <= fromBalance
        }
    }

    func buildApprovePayload(tx: SwapTransaction) async throws -> ERC20ApprovePayload? {
        guard tx.isApproveRequired, let spender = tx.router else {
            return nil
        }
        let amount = tx.amountInCoinDecimal
        let payload = ERC20ApprovePayload(amount: amount, spender: spender)
        return payload
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
        currentTitle = titles[currentIndex-1]
    }
    
    func buildSwapKeysignPayload(tx: SwapTransaction, vault: Vault) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        
        do {
            guard let quote = tx.quote else {
                throw Errors.unexpectedError
            }

            let chainSpecific = try await blockchainService.fetchSpecific(tx: tx)

            let toAddress = quote.router ?? quote.inboundAddress ?? tx.fromCoin.address

            switch quote {
            case .mayachain(let quote):
                keysignPayload = try await KeysignPayloadFactory().buildTransfer(
                    coin: tx.fromCoin,
                    toAddress: toAddress,
                    amount: tx.amountInCoinDecimal,
                    memo: tx.quote?.memo,
                    chainSpecific: chainSpecific,
                    swapPayload: .mayachain(tx.buildThorchainSwapPayload(
                        quote: quote,
                        provider: .mayachain
                    )),
                    approvePayload: buildApprovePayload(tx: tx),
                    vault: vault
                )

                return true

            case .thorchain(let quote):
                keysignPayload = try await KeysignPayloadFactory().buildTransfer(
                    coin: tx.fromCoin,
                    toAddress: toAddress,
                    amount: tx.amountInCoinDecimal,
                    memo: tx.quote?.memo,
                    chainSpecific: chainSpecific,
                    swapPayload: .thorchain(tx.buildThorchainSwapPayload(
                        quote: quote,
                        provider: .thorchain
                    )),
                    approvePayload: buildApprovePayload(tx: tx),
                    vault: vault
                )
                
                return true

            case .oneinch(let quote), .lifi(let quote):
                let keysignFactory = KeysignPayloadFactory()
                let payload = OneInchSwapPayload(
                    fromCoin: tx.fromCoin,
                    toCoin: tx.toCoin,
                    fromAmount: tx.amountInCoinDecimal,
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
                    approvePayload: buildApprovePayload(tx: tx),
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
    
    func stopMediator() {
        Mediator.shared.stop()
    }

    func switchCoins(tx: SwapTransaction, vault: Vault) {
        let fromCoin = tx.fromCoin
        let toCoin = tx.toCoin
        tx.fromCoin = toCoin
        tx.toCoin = fromCoin
        fetchFees(tx: tx, vault: vault)
        fetchQuotes(tx: tx, vault: vault)
    }

    func updateFromAmount(tx: SwapTransaction, vault: Vault) {
        fetchQuotes(tx: tx, vault: vault)
    }
    
    func updateFromCoin(coin: Coin, tx: SwapTransaction, vault: Vault) {
        tx.fromCoin = coin
        fetchFees(tx: tx, vault: vault)
        fetchQuotes(tx: tx, vault: vault)
    }
    
    func updateToCoin(coin: Coin, tx: SwapTransaction, vault: Vault) {
        tx.toCoin = coin
        fetchQuotes(tx: tx, vault: vault)
    }
    
    func handleBackTap() {
        currentIndex-=1
        currentTitle = titles[currentIndex-1]
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
    
    func updateQuotes(tx: SwapTransaction, vault: Vault) async {
        quoteLoading = true
        defer { quoteLoading = false }
        
        clearQuote(tx: tx)
        
        error = nil

        guard !tx.fromAmount.isEmpty else { return }

        do {
            guard !tx.fromAmountDecimal.isZero, tx.fromCoin != tx.toCoin else {
                return
            }
            
            let quote = try await swapService.fetchQuote(
                amount: tx.fromAmountDecimal,
                fromCoin: tx.fromCoin,
                toCoin: tx.toCoin,
                isAffiliate: tx.isAlliliate
            )
            
            switch quote {
            case .oneinch(let quote), .lifi(let quote):
                tx.oneInchFee = oneInchFee(quote: quote)
            case .thorchain, .mayachain: 
                break
            }
            
            tx.quote = quote

            if !isSufficientBalance(tx: tx) {
                throw Errors.insufficientFunds
            }
        } catch {
            self.error = error
        }
    }
    
    func updateFees(tx: SwapTransaction, vault: Vault) async {
        tx.gas = .zero
        tx.thorchainFee = .zero

        do {
            let chainSpecific = try await blockchainService.fetchSpecific(tx: tx)

            tx.thorchainFee = try await thorchainFee(for: chainSpecific, tx: tx, vault: vault)
            tx.gas = chainSpecific.gas
        } catch {
            print("Update fees error: \(error.localizedDescription)")
        }
    }
    
    func clearQuote(tx: SwapTransaction) {
        tx.quote = nil
    }
    
    func feeCoin(tx: SwapTransaction) -> Coin {
        switch tx.fromCoin.chainType {
        case .UTXO, .Solana, .THORChain, .Cosmos, .Polkadot, .Sui:
            return tx.fromCoin
        case .EVM:
            guard !tx.fromCoin.isNativeToken else { return tx.fromCoin }
            return tx.fromCoins.first(where: { $0.chain == tx.fromCoin.chain && $0.isNativeToken }) ?? tx.fromCoin
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
            let plan = try utxo.getBitcoinTransactionPlan(keysignPayload: keysignPayload)
            return BigInt(plan.fee)

        case .Cosmos, .THORChain, .Polkadot, .MayaChain, .Solana, .Sui:
            return chainSpecific.gas
        }
    }
    
    func oneInchFee(quote: OneInchQuote) -> BigInt {
        let gasPrice = BigInt(quote.tx.gasPrice) ?? BigInt.zero
        return gasPrice * BigInt(EVMHelper.defaultETHSwapGasUnit)
    }

    func fetchFees(tx: SwapTransaction, vault: Vault) {
        updateFeesTask?.cancel()
        updateFeesTask = Task {
            await updateFees(tx: tx, vault: vault)
        }
    }

    func fetchQuotes(tx: SwapTransaction, vault: Vault) {
        updateQuoteTask?.cancel()
        updateQuoteTask = Task {
            await updateQuotes(tx: tx, vault: vault)
        }
    }
}
