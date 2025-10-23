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

@MainActor
class SwapCryptoViewModel: ObservableObject, TransferViewModel {
    private let titles = ["swap", "swapOverview", "pair", "keysign", "done"]
    
    private let swapService = SwapService.shared
    private let blockchainService = BlockChainService.shared
    private let fastVaultService = FastVaultService.shared
    
    private var updateQuoteTask: Task<Void, Never>?
    private var updateFeesTask: Task<Void, Never>?
    
    var keysignPayload: KeysignPayload?
    
    @Published var currentIndex = 1
    @Published var currentTitle = "swap"
    @Published var hash: String?
    @Published var approveHash: String?
    
    @Published var error: Error?
    @Published var isLoading = false
    @Published var isLoadingQuotes = false
    @Published var isLoadingFees = false
    @Published var isLoadingTransaction = false
    @Published var dataLoaded = false
    @Published var timer: Int = 59
    
    @Published var fromChain: Chain? = nil
    @Published var toChain: Chain? = nil
    @Published var showFromChainSelector = false
    @Published var showToChainSelector = false
    @Published var showFromCoinSelector = false
    @Published var showToCoinSelector = false
    @Published var showAllPercentageButtons = true
    
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
        let isExist = await fastVaultService.exist(pubKeyECDSA: vault.pubKeyECDSA)
        let isLocalBackup = vault.localPartyID.lowercased().contains("server-")
        tx.isFastVault = isExist && !isLocalBackup
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
        case .thorchainStagenet:
            return Endpoint.getStagenetSwapProgressURL(txid: hash)
        case .mayachain:
            return Endpoint.getMayaSwapTracker(txid: hash)
        case .lifi:
            return Endpoint.getLifiSwapTracker(txid: hash)
        case .oneinch, .kyberswap, .none:
            return Endpoint.getExplorerURL(chain: tx.fromCoin.chain, txid: hash)
        }
    }
    
    func fromFiatAmount(tx: SwapTransaction) -> String {
        let fiatDecimal = tx.fromCoin.fiat(decimal: tx.fromAmountDecimal)
        return fiatDecimal.formatForDisplay()
    }
    
    func toFiatAmount(tx: SwapTransaction) -> String {
        let fiatDecimal = tx.toCoin.fiat(decimal: tx.toAmountDecimal)
        return fiatDecimal.formatForDisplay()
    }
    
    func showGas(tx: SwapTransaction) -> Bool {
        return !tx.gas.isZero
    }
    
    func showFees(tx: SwapTransaction) -> Bool {
        let fee = swapFeeString(tx: tx)
        return !fee.isEmpty && !fee.isZero
    }
    
    func showTotalFees(tx: SwapTransaction) -> Bool {
        let fee = totalFeeString(tx: tx)
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
        
        // Use tx.fee for swap quotes (which includes corrected gas price calculations)
        // Fall back to tx.gas for other transaction types
        let gasValue = tx.quote != nil ? tx.fee : tx.gas
        
        if coin.chain.chainType == .EVM {
            guard let weiPerGWeiDecimal = Decimal(string: EVMHelper.weiPerGWei.description) else {
                return .empty
            }
            return "\((Decimal(gasValue) / weiPerGWeiDecimal).formatToDecimal(digits: 0).description) \(coin.chain.feeUnit)"
        } else if coin.chain.chainType == .UTXO {
            // for UTXO chains , we use transaction plan to get the transaction fee in total
            return "\((Decimal(gasValue) / pow(10 ,decimals)).formatToDecimal(digits: decimals).description) \(coin.ticker)"
        } else {
            return "\((Decimal(gasValue) / pow(10 ,decimals)).formatToDecimal(digits: decimals).description) \(coin.ticker)"
        }
    }
    
    func approveFeeString(tx: SwapTransaction) -> String {
        let fromCoin = feeCoin(tx: tx)
        let fee = fromCoin.fiat(gas: tx.fee)
        return fee.formatToFiat(includeCurrencySymbol: true)
    }
    
    func totalFeeString(tx: SwapTransaction) -> String {
        guard let inboundFeeDecimal = tx.inboundFeeDecimal else { return .empty }
        
        let fromCoin = feeCoin(tx: tx)
        let inboundFee = tx.toCoin.raw(for: inboundFeeDecimal)
        let providerFee = tx.toCoin.fiat(value: inboundFee)
        let networkFee = fromCoin.fiat(gas: tx.fee)
        let totalFee = providerFee + networkFee
        return totalFee.formatToFiat(includeCurrencySymbol: true)
    }
    
    func isSufficientBalance(tx: SwapTransaction) -> Bool {
        let feeCoin = feeCoin(tx: tx)
        let fromFee = feeCoin.decimal(for: tx.fee)
        
        let fromBalance = tx.fromCoin.balanceDecimal
        let feeCoinBalance = feeCoin.balanceDecimal
        
        let amount = tx.fromAmount.toDecimal()
        
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
        // Approve exact amount - no buffer needed for KyberSwap precision
        let payload = ERC20ApprovePayload(amount: tx.amountInCoinDecimal, spender: spender)
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
        && tx.gas != .zero
        && isSufficientBalance(tx: tx)
        && !isLoading
    }
    
    func moveToNextView() {
        currentIndex += 1
        currentTitle = titles[currentIndex-1]
    }
    
    func buildSwapKeysignPayload(tx: SwapTransaction, vault: Vault) async -> Bool {
        isLoadingTransaction = true
        defer { isLoadingTransaction = false }
        
        do {
            guard let quote = tx.quote else {
                throw Errors.unexpectedError
            }
            
            let chainSpecific = try await blockchainService.fetchSpecific(tx: tx)
            
            switch quote {
            case .mayachain(let quote):
                let toAddress = tx.fromCoin.isNativeToken ? quote.inboundAddress : quote.router
                keysignPayload = try await KeysignPayloadFactory().buildTransfer(
                    coin: tx.fromCoin,
                    toAddress: toAddress ?? tx.fromCoin.address,
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
                let toAddress = quote.router ?? quote.inboundAddress ?? tx.fromCoin.address
                keysignPayload = try await KeysignPayloadFactory().buildTransfer(
                    coin: tx.fromCoin,
                    toAddress: toAddress,
                    amount: tx.amountInCoinDecimal,
                    memo: quote.memo,
                    chainSpecific: chainSpecific,
                    swapPayload: .thorchain(tx.buildThorchainSwapPayload(
                        quote: quote,
                        provider: .thorchain
                    )),
                    approvePayload: buildApprovePayload(tx: tx),
                    vault: vault
                )
                
                return true
                
            case .thorchainStagenet(let quote):
                let toAddress = quote.router ?? quote.inboundAddress ?? tx.fromCoin.address
                keysignPayload = try await KeysignPayloadFactory().buildTransfer(
                    coin: tx.fromCoin,
                    toAddress: toAddress,
                    amount: tx.amountInCoinDecimal,
                    memo: quote.memo,
                    chainSpecific: chainSpecific,
                    swapPayload: .thorchainStagenet(tx.buildThorchainSwapPayload(
                        quote: quote,
                        provider: .thorchainStagenet
                    )),
                    approvePayload: buildApprovePayload(tx: tx),
                    vault: vault
                )
                
                return true
                
            case .oneinch(let evmQuote, _), .lifi(let evmQuote, _, _), .kyberswap(let evmQuote, _):
                let keysignFactory = KeysignPayloadFactory()
                let payload = GenericSwapPayload(
                    fromCoin: tx.fromCoin,
                    toCoin: tx.toCoin,
                    fromAmount: tx.amountInCoinDecimal,
                    toAmountDecimal: tx.toAmountDecimal,
                    quote: evmQuote,
                    provider: quote.swapProviderId ?? .oneInch
                )
                keysignPayload = try await keysignFactory.buildTransfer(
                    coin: tx.fromCoin,
                    toAddress: evmQuote.tx.to,
                    amount: tx.amountInCoinDecimal,
                    memo: nil,
                    chainSpecific: chainSpecific,
                    swapPayload: .generic(payload),
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
    
    func switchCoins(tx: SwapTransaction, vault: Vault, referredCode: String) {
        let fromCoin = tx.fromCoin
        let toCoin = tx.toCoin
        tx.fromCoin = toCoin
        tx.toCoin = fromCoin
        fetchQuotes(tx: tx, vault: vault, referredCode: referredCode)
    }
    
    func updateFromAmount(tx: SwapTransaction, vault: Vault, referredCode: String) {
        fetchQuotes(tx: tx, vault: vault, referredCode: referredCode)
    }
    
    func updateFromCoin(coin: Coin, tx: SwapTransaction, vault: Vault, referredCode: String) {
        tx.fromCoin = coin
        fromChain = coin.chain
        fetchQuotes(tx: tx, vault: vault, referredCode: referredCode)
        updateBalance(for: coin)
    }
    
    func updateToCoin(coin: Coin, tx: SwapTransaction, vault: Vault, referredCode: String) {
        tx.toCoin = coin
        toChain = coin.chain
        fetchQuotes(tx: tx, vault: vault, referredCode: referredCode)
        updateBalance(for: coin)
    }
    
    func updateBalance(for coin: Coin) {
        Task {
            await BalanceService.shared.updateBalance(for: coin)
        }
    }
    
    func handleBackTap() {
        currentIndex-=1
        currentTitle = titles[currentIndex-1]
    }
    
    func updateTimer(tx: SwapTransaction, vault: Vault, referredCode: String) {
        timer -= 1
        
        if timer < 1 {
            restartTimer(tx: tx, vault: vault, referredCode: referredCode)
        }
    }
    
    func restartTimer(tx: SwapTransaction, vault: Vault, referredCode: String) {
        refreshData(tx: tx, vault: vault, referredCode: referredCode)
        timer = 59
    }
    
    func refreshData(tx: SwapTransaction, vault: Vault, referredCode: String) {
        fetchQuotes(tx: tx, vault: vault, referredCode: referredCode)
    }
    
    func fetchFees(tx: SwapTransaction, vault: Vault) {
        updateFeesTask?.cancel()
        updateFeesTask = Task {[weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds delay
            guard !Task.isCancelled else { return }
            await self?.updateFees(tx: tx, vault: vault)
        }
    }
    
    func fetchQuotes(tx: SwapTransaction, vault: Vault, referredCode: String) {
        // this method is called when the user changes the amount, from/to coins, or chains
        // it will update the quotes after a short delay to avoid excessive requests
        updateQuoteTask?.cancel()
        updateQuoteTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds delay
            guard !Task.isCancelled else { return }
            await self?.updateQuotes(tx: tx, vault: vault, referredCode: referredCode)
            await self?.updateFees(tx: tx, vault: vault)
        }
    }
    
    func pickerFromCoins(tx: SwapTransaction) -> [Coin] {
        return tx.fromCoins.filter({ coin in
            coin.chain == fromChain
        }).sorted(by: {
            Int($0.chain == tx.fromCoin.chain) > Int($1.chain == tx.fromCoin.chain)
        })
    }
    
    func pickerToCoins(tx: SwapTransaction) -> [Coin] {
        return tx.toCoins.filter({ coin in
            coin.chain == toChain
        }).sorted(by: {
            Int($0.chain == tx.toCoin.chain) > Int($1.chain == tx.toCoin.chain)
        })
    }
}

private extension SwapCryptoViewModel {
    
    enum Errors: String, Error, LocalizedError {
        case unexpectedError
        case insufficientFunds
        case swapAmountTooSmall
        case inboundAddress
        
        var errorDescription: String? {
            switch self {
            case .unexpectedError:
                return "Unexpected swap error"
            case .insufficientFunds:
                return "Insufficient funds"
            case .swapAmountTooSmall:
                return "Swap amount too small"
            case .inboundAddress:
                return "Inbound address is invalid"
            }
        }
    }
    
    func updateQuotes(tx: SwapTransaction, vault: Vault, referredCode: String) async {
        isLoadingQuotes = true
        defer { isLoadingQuotes = false }
        
        clearQuote(tx: tx)
        
        error = nil
        
        guard !tx.fromAmount.isEmpty else { return }
        
        do {
            guard !tx.fromAmountDecimal.isZero, tx.fromCoin != tx.toCoin else {
                return
            }
            
            let vultTier = await VultTierService().fetchDiscountTier(for: vault)
            let quote = try await swapService.fetchQuote(
                amount: tx.fromAmountDecimal,
                fromCoin: tx.fromCoin,
                toCoin: tx.toCoin,
                isAffiliate: tx.isAffiliate,
                referredCode: referredCode,
                vultTierDiscount: vultTier?.bpsDiscount ?? 0
            )
            
            tx.quote = quote
            if !isSufficientBalance(tx: tx) {
                throw Errors.insufficientFunds
            }
        } catch {
            if let error = error as? URLError, error.code == .cancelled {
                print("request cancelled")
            } else {
                self.error = error
            }
        }
    }
    
    func updateFees(tx: SwapTransaction, vault: Vault) async {
        isLoadingFees = true
        defer { isLoadingFees = false }
        
        tx.gas = .zero
        tx.thorchainFee = .zero
        
        // Skip fee calculation if no amount is entered
        guard !tx.fromAmount.isEmpty, !tx.fromAmountDecimal.isZero else {
            return
        }
        
        do {
            let chainSpecific = try await blockchainService.fetchSpecific(tx: tx)
            print("Fetched chain specific: \(chainSpecific)")
            tx.gas = chainSpecific.gas
            tx.thorchainFee = try await thorchainFee(for: chainSpecific, tx: tx, vault: vault)

        } catch {
            print("Update fees error: \(error.localizedDescription)")
            
            // Handle UTXO-specific errors for better user experience
            switch error {
            case KeysignPayloadFactory.Errors.notEnoughUTXOError,
                 KeysignPayloadFactory.Errors.utxoTooSmallError,
                 KeysignPayloadFactory.Errors.utxoSelectionFailedError:
                // These are UTXO-specific errors that should be shown directly
                self.error = error
            default:
                self.error = Errors.insufficientFunds
            }
        }
    }
    
    func clearQuote(tx: SwapTransaction) {
        tx.quote = nil
    }
    
    func feeCoin(tx: SwapTransaction) -> Coin {
        // Fees are always paid in native token
        guard !tx.fromCoin.isNativeToken else { return tx.fromCoin }
        return tx.fromCoins.first(where: { $0.chain == tx.fromCoin.chain && $0.isNativeToken }) ?? tx.fromCoin
    }
    
    func thorchainFee(for chainSpecific: BlockChainSpecific, tx: SwapTransaction, vault: Vault) async throws -> BigInt {
        switch chainSpecific {
        case .Ethereum(let maxFeePerGas, let priorityFee, _, let gasLimit):
            return (maxFeePerGas + priorityFee) * gasLimit
        case .UTXO, .Cardano:
            let keysignFactory = KeysignPayloadFactory()
            do {
                let keysignPayload = try await keysignFactory.buildTransfer(
                    coin: tx.fromCoin,
                    toAddress: tx.fromCoin.address,
                    amount: tx.amountInCoinDecimal,
                    memo: nil,
                    chainSpecific: chainSpecific,
                    swapPayload: nil,
                    vault: vault
                )
                
                let planFee: BigInt
                switch tx.fromCoin.chain {
                case .cardano:
                    guard let cardanoHelper = CardanoHelper.getHelper(vault: vault, coin: tx.fromCoin) else {
                        throw Errors.insufficientFunds
                    }
                    planFee = try cardanoHelper.calculateDynamicFee(keysignPayload: keysignPayload)
                    
                default: // UTXO chains
                    let utxo = UTXOChainsHelper(
                        coin: tx.fromCoin.coinType,
                        vaultHexPublicKey: vault.pubKeyECDSA,
                        vaultHexChainCode: vault.hexChainCode
                    )
                    let plan = try utxo.getBitcoinTransactionPlan(keysignPayload: keysignPayload)
                    planFee = BigInt(plan.fee)
                }
                
                if planFee <= 0 && tx.fromAmountDecimal > 0 {
                    throw Errors.insufficientFunds
                }
                return planFee
            } catch {
                // Re-throw specific errors to provide better user feedback
                if error is KeysignPayloadFactory.Errors {
                    throw error
                }
                throw Errors.insufficientFunds
            }
            
        case .Cosmos, .THORChain, .Polkadot, .MayaChain, .Solana, .Sui, .Ton, .Ripple, .Tron:
            return chainSpecific.gas
        }
    }
}

// MARK: - Asset Selection

extension SwapCryptoViewModel {
    func handleFromChainUpdate(tx: SwapTransaction, vault: Vault) {
        guard
            let fromChain,
            fromChain != tx.fromCoin.chain,
            let coin = getDefaultCoin(for: fromChain, vault: vault)
        else { return }
        tx.fromCoin = coin
    }
    
    func handleToChainUpdate(tx: SwapTransaction, vault: Vault) {
        guard
            let toChain,
            toChain != tx.toCoin.chain,
            let coin = getDefaultCoin(for: toChain, vault: vault) else { return }
        tx.toCoin = coin
    }
    
    func getDefaultCoin(for chain: Chain, vault: Vault) -> Coin? {
        let firstVaultCoin = vault.coins
            .filter { $0.chain == chain }
            .sorted { $0.balanceInFiatDecimal > $1.balanceInFiatDecimal }
            .first

        if let firstVaultCoin {
            return firstVaultCoin
        } else {
            let coinMeta = TokensStore.TokenSelectionAssets
                .filter { $0.chain == chain }
                .sorted { $0.isNativeToken && !$1.isNativeToken }
                .first
            guard let coinMeta, let coin = try? CoinFactory.create(asset: coinMeta,
                                                                   publicKeyECDSA: vault.pubKeyECDSA,
                                                                   publicKeyEdDSA: vault.pubKeyEdDSA,
                                                                   hexChainCode: vault.hexChainCode) else {
                return nil
            }
            return coin
        }
    }
}
