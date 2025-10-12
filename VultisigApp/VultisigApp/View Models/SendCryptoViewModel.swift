//
//  SendCryptoDetailsViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-15.
//

import SwiftUI
import BigInt
import OSLog
import WalletCore
import Mediator

@MainActor
class SendCryptoViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var isValidatingForm = false
    @Published var isValidAddress = false
    @Published var isValidForm = true
    @Published var isNamespaceResolved = false
    @Published var showAlert = false
    @Published var currentIndex = 1
    @Published var currentTitle = "send"
    @Published var errorTitle = ""
    @Published var errorMessage = ""
    @Published var hash: String? = nil
    @Published var approveHash: String? = nil
    
    @Published var sol: SolanaService = SolanaService.shared
    @Published var sui: SuiService = SuiService.shared
    @Published var ton: TonService = TonService.shared
    
    @Published var utxo = BlockchairService.shared
    @Published var ripple: RippleService = RippleService.shared
    
    @Published var tron: TronService = TronService.shared
    
    @Published var showAddressAlert: Bool = false
    @Published var showAmountAlert: Bool = false
    @Published var hasPendingTransaction: Bool = false
    @Published var pendingTransactionCountdown: Int = 0
    @Published var isCheckingPendingTransactions: Bool = false
    
    let blockchainService = BlockChainService.shared
    
    private let mediator = Mediator.shared
    private let fastVaultService = FastVaultService.shared
    
    let logger = Logger(subsystem: "send-input-details", category: "transaction")
    
    var continueButtonDisabled: Bool {
        isLoading || isValidatingForm
    }
    
    /// Initialize pending transaction state based on chain
    func initializePendingTransactionState(for chain: Chain) {
        if chain.supportsPendingTransactions {
            isCheckingPendingTransactions = true
        } else {
            isCheckingPendingTransactions = false
            hasPendingTransaction = false
            pendingTransactionCountdown = 0
        }
    }
    
    var showLoader: Bool {
        isValidatingForm
    }
    
    func loadGasInfoForSending(tx: SendTransaction) async {
        guard !isLoading else {
            return
        }
        isLoading = true
        defer {
            isLoading = false
        }
        do {
            let specific = try await blockchainService.fetchSpecific(tx: tx)
            tx.gas = specific.gas
            
            // For UTXO and Cardano chains, calculate actual total fee using WalletCore plan.fee (like Android)
            if tx.coin.chainType == .UTXO || tx.coin.chainType == .Cardano {
                if tx.amountInRaw > 0 {
                    // Only calculate accurate fee when user has entered an amount
                    tx.fee = try await calculatePlanFee(tx: tx, chainSpecific: specific)
                } else {
                    // Initial state - no amount yet, use 0 to indicate fee not calculated yet
                    tx.fee = BigInt.zero
                }
            } else {
                tx.fee = specific.fee
            }
            
            tx.estematedGasLimit = specific.gasLimit
        } catch {
            print("error fetching data: \(error.localizedDescription)")
        }
        
    }
    
    func loadFastVault(tx: SendTransaction, vault: Vault) async {
        let isExist = await fastVaultService.exist(pubKeyECDSA: vault.pubKeyECDSA)
        let isLocalBackup = vault.localPartyID.lowercased().contains("server-")
        
        tx.isFastVault = isExist && !isLocalBackup
    }
    
    // TODO: Refactor to remove duplication
    func setMaxValues(tx: SendTransaction, percentage: Double = 100) {
        errorMessage = ""
        let coinName = tx.coin.chain.name.lowercased()
        let key: String = "\(tx.fromAddress)-\(coinName)"
        isLoading = true
        switch tx.coin.chain {
        case .bitcoin,.dogecoin,.litecoin,.bitcoinCash,.dash, .zcash:
            Task {
                tx.sendMaxAmount = percentage == 100 // Never set this to true if the percentage is not 100, otherwise it will wipe your wallet.
                tx.amount = await utxo.getByKey(key: key)?.address?.balanceInBTC ?? "0.0"
                setPercentageAmount(tx: tx, for: percentage)
                convertToFiat(newValue: tx.amount, tx: tx, setMaxValue: tx.sendMaxAmount)
                isLoading = false
            }
        case .cardano:
            tx.sendMaxAmount = percentage == 100 // Never set this to true if the percentage is not 100, otherwise it will wipe your wallet.
            Task {
                await BalanceService.shared.updateBalance(for: tx.coin)
                
                let gas = BigInt.zero
                // For Cardano, use decimals - 1 to match getMaxValue truncation
                let maxDecimals = tx.coin.decimals > 0 ? tx.coin.decimals - 1 : tx.coin.decimals
                tx.amount = "\(tx.coin.getMaxValue(gas).formatToDecimal(digits: maxDecimals))"
                setPercentageAmount(tx: tx, for: percentage)
                
                convertToFiat(newValue: tx.amount, tx: tx, setMaxValue: tx.sendMaxAmount)
                
                isLoading = false
            }
        case .ethereum, .avalanche, .bscChain, .arbitrum, .base, .optimism, .polygon, .polygonV2, .blast, .cronosChain, .zksync,.ethereumSepolia, .mantle:
            Task {
                do {
                    if tx.coin.isNativeToken {
                        let evm = try await blockchainService.fetchSpecific(tx: tx)
                        let totalFeeWei = evm.fee
                        tx.amount = "\(tx.coin.getMaxValue(totalFeeWei).formatToDecimal(digits: tx.coin.decimals))" // the decimals must be truncaded otherwise the give us precisions errors
                        setPercentageAmount(tx: tx, for: percentage)
                    } else {
                        tx.amount = "\(tx.coin.getMaxValue(0))"
                        setPercentageAmount(tx: tx, for: percentage)
                    }
                } catch {
                    tx.amount = "\(tx.coin.getMaxValue(0))"
                    setPercentageAmount(tx: tx, for: percentage)
                    print("Failed to get EVM balance, error: \(error.localizedDescription)")
                }
                
                convertToFiat(newValue: tx.amount, tx: tx)
                isLoading = false
            }
            
        case .solana:
            Task {
                do{
                    if tx.coin.isNativeToken {
                        let rawBalance = try await sol.getSolanaBalance(coin: tx.coin)
                        tx.coin.rawBalance = rawBalance
                        tx.amount = "\(tx.coin.getMaxValue(SolanaHelper.defaultFeeInLamports).formatToDecimal(digits: tx.coin.decimals))"
                        setPercentageAmount(tx: tx, for: percentage)
                    } else {
                        
                        tx.amount = "\(tx.coin.getMaxValue(0))"
                        setPercentageAmount(tx: tx, for: percentage)
                    }
                } catch {
                    tx.amount = "\(tx.coin.getMaxValue(0))"
                    setPercentageAmount(tx: tx, for: percentage)
                    print("Failed to get SOLANA balance, error: \(error.localizedDescription)")
                }
                
                convertToFiat(newValue: tx.amount, tx: tx)
                isLoading = false
            }
        case .sui:
            Task {
                do {
                    let rawBalance = try await sui.getBalance(coin: tx.coin)
                    tx.coin.rawBalance = rawBalance
                    
                    if tx.coin.isNativeToken {
                        
                        var gas = BigInt.zero
                        if percentage == 100 {
                            gas = tx.coin.feeDefault.toBigInt()
                        }
                        
                        tx.amount = "\(tx.coin.getMaxValue(gas).formatToDecimal(digits: tx.coin.decimals))"
                        setPercentageAmount(tx: tx, for: percentage)
                        
                        convertToFiat(newValue: tx.amount, tx: tx)
                    } else {
                        
                        tx.amount = "\(tx.coin.getMaxValue(0))"
                        setPercentageAmount(tx: tx, for: percentage)
                        
                    }
                } catch {
                    print("fail to load SUI balances,error:\(error.localizedDescription)")
                }
                
                isLoading = false
            }
        case .kujira, .gaiaChain, .mayaChain, .thorChain, .dydx, .osmosis, .terra, .terraClassic, .noble, .akash:
            Task {
                await BalanceService.shared.updateBalance(for: tx.coin)
                
                var gas = BigInt.zero
                
                if percentage == 100 {
                    gas = BigInt(tx.gasDecimal.description,radix:10) ?? 0
                }
                
                tx.amount = "\(tx.coin.getMaxValue(gas).formatToDecimal(digits: tx.coin.decimals))"
                setPercentageAmount(tx: tx, for: percentage)
                
                convertToFiat(newValue: tx.amount, tx: tx)
                
                isLoading = false
            }
        case .polkadot:
            Task {
                do {
                    tx.sendMaxAmount = percentage == 100 // Set sendMaxAmount flag for max sends
                    await BalanceService.shared.updateBalance(for: tx.coin)
                    
                    var gas = BigInt.zero
                    let dot = try await blockchainService.fetchSpecific(tx: tx)
                    gas = dot.gas
                    
                    tx.amount = "\(tx.coin.getMaxValue(gas).formatToDecimal(digits: tx.coin.decimals))"
                    setPercentageAmount(tx: tx, for: percentage)
                    
                    convertToFiat(newValue: tx.amount, tx: tx, setMaxValue: tx.sendMaxAmount)
                } catch {
                    tx.amount = "\(tx.coin.getMaxValue(0))"
                    setPercentageAmount(tx: tx, for: percentage)
                    convertToFiat(newValue: tx.amount, tx: tx, setMaxValue: tx.sendMaxAmount)
                    print("Failed to get Polkadot dynamic fee, error: \(error.localizedDescription)")
                }
                
                isLoading = false
            }
        case .ton:
            Task {
                do {
                    tx.sendMaxAmount = percentage == 100 // Never set this to true if the percentage is not 100, otherwise it will wipe your wallet.
                    let rawBalance: String
                    if tx.coin.isNativeToken {
                        rawBalance = try await ton.getBalance(tx.coin)
                    } else {
                        rawBalance = try await ton.getJettonBalance(tx.coin)
                    }

                    tx.coin.rawBalance = rawBalance

                    let gasForMax: BigInt = tx.coin.isNativeToken && percentage != 100 ? TonHelper.defaultFee : 0

                    tx.amount = "\(tx.coin.getMaxValue(gasForMax).formatToDecimal(digits: tx.coin.decimals))"
                    
                    setPercentageAmount(tx: tx, for: percentage)

                    convertToFiat(newValue: tx.amount, tx: tx, setMaxValue: tx.sendMaxAmount)
                } catch {
                    print("fail to load ton balances,error:\(error.localizedDescription)")
                }

                isLoading = false
            }
        case .ripple:
            Task {
                do {
                    let rawBalance = try await ripple.getBalance(tx.coin)
                    tx.coin.rawBalance = rawBalance
                    
                    var gas = BigInt.zero
                    if percentage == 100 {
                        gas = tx.coin.feeDefault.toBigInt()
                    }
                    
                    tx.amount = "\(tx.coin.getMaxValue(gas).formatToDecimal(digits: tx.coin.decimals))"
                    setPercentageAmount(tx: tx, for: percentage)
                    
                    convertToFiat(newValue: tx.amount, tx: tx)
                } catch {
                    print("fail to load ripple balances,error:\(error.localizedDescription)")
                }
                
                isLoading = false
            }
            
        case .tron:
            Task {
                do {
                    let rawBalance = try await tron.getBalance(coin: tx.coin)
                    tx.coin.rawBalance = rawBalance
                    
                    var gas = BigInt.zero
                    if percentage == 100 {
                        gas = tx.coin.feeDefault.toBigInt()
                    }
                    
                    tx.amount = "\(tx.coin.getMaxValue(gas).formatToDecimal(digits: tx.coin.decimals))"
                    setPercentageAmount(tx: tx, for: percentage)
                    
                    convertToFiat(newValue: tx.amount, tx: tx)
                } catch {
                    print("fail to load TRON balances,error:\(error.localizedDescription)")
                }
                
                isLoading = false
            }
            
        }
    }
    
    private func setPercentageAmount(tx: SendTransaction, for percentage: Double) {
        let max = tx.amount
        let multiplier = (Decimal(percentage) / 100)
        let amountDecimal = max.toDecimal() * multiplier
        tx.amount = amountDecimal.formatToDecimal(digits: tx.coin.decimals)
    }
    
    func convertFiatToCoin(newValue: String, tx: SendTransaction) {
        let newValueDecimal = newValue.toDecimal()
        if newValueDecimal > 0 {
            let newValueCoin = newValueDecimal / Decimal(tx.coin.price)
            let truncatedValueCoin = newValueCoin.truncated(toPlaces: tx.coin.decimals)
            tx.amount = truncatedValueCoin.formatToDecimal(digits: tx.coin.decimals)
            tx.sendMaxAmount = false
        } else {
            tx.amount = ""
        }
    }
    
    func convertToFiat(newValue: String, tx: SendTransaction, setMaxValue: Bool = false) {
        let newValueDecimal = newValue.toDecimal()
        if newValueDecimal > 0 {
            let newValueFiat = newValueDecimal * Decimal(tx.coin.price)
            let truncatedValueFiat = newValueFiat.truncated(toPlaces: 2) // Assuming 2 decimal places for fiat
            tx.amountInFiat = truncatedValueFiat.formatToDecimal(digits: tx.coin.decimals)
            tx.sendMaxAmount = setMaxValue
            
            // Recalculate plan-based fees when amount changes (UTXO and Cardano chains)
            recalculatePlanFeesIfNeeded(tx: tx)
        } else {
            tx.amountInFiat = ""
        }
    }
    
    func validateAddress(tx: SendTransaction, address: String) {
        guard !isNamespaceResolved else {
            return isValidAddress = true
        }
        isValidAddress = AddressService.validateAddress(address: address, chain: tx.coin.chain)
    }
    
    func validateAmount(amount: String) {
        errorTitle = ""
        errorMessage = ""
        isValidForm = true
        
        isValidForm = amount.isValidDecimal()
        
        if !isValidForm {
            errorTitle = "error"
            errorMessage = "The amount must be decimal."
            showAlert = true
        }
    }
    
    func validateForm(tx: SendTransaction) async -> Bool {
        // Reset validation state at the beginning
        resetStates()
        
        // Check for pending Cosmos transactions that could cause nonce conflicts
        if await hasPendingCosmosTransactions(tx: tx) {
            return false
        }
        
        let amount = tx.amountDecimal
        let gasFee = tx.gasDecimal
        
        if amount <= 0 {
            errorTitle = "error"
            errorMessage = "positiveAmountError"
            showAmountAlert = true
            logger.log("Invalid or non-positive amount.")
            isValidForm = false
            isLoading = false
            return isValidForm
        }
        
        if gasFee == 0 && !tx.coin.allowZeroGas() {
            errorTitle = "error"
            errorMessage = "noGasEstimation"
            showAmountAlert = true
            logger.log("No gas estimation.")
            isValidForm = false
            isLoading = false
            return isValidForm
        }
        
        if gasFee < 0 {
            errorTitle = "error"
            errorMessage = "nonNegativeFeeError"
            showAmountAlert = true
            logger.log("Invalid or negative fee.")
            isValidForm = false
            isLoading = false
            return isValidForm
        }
        
        if tx.isAmountExceeded {
            errorTitle = "error"
            errorMessage = "walletBalanceExceededError"
            showAmountAlert = true
            logger.log("Total transaction cost exceeds wallet balance.")
            isValidForm = false
            isLoading = false
            return isValidForm
        }
        // check UTXO minimum amount and fee validation
        if tx.coin.chainType == .UTXO {
            let dustThreshold = tx.coin.coinType.getFixedDustThreshold()
            if tx.amountInRaw < dustThreshold {
                errorTitle = "error"
                errorMessage = "amount is below the dust threshold."
                showAmountAlert = true
                isValidForm = false
                isLoading = false
                return isValidForm
            }
            
            // Check if WalletCore returned 0 fee (insufficient balance for UTXO transaction)
            if tx.fee == 0 && tx.amountInRaw > 0 {
                errorTitle = "error"
                errorMessage = "walletBalanceExceededError"
                showAmountAlert = true
                logger.log("Insufficient UTXO balance to cover transaction and fees.")
                isValidForm = false
                isLoading = false
                return isValidForm
            }
        }
        let validToAddress =  await validateToAddress(tx: tx)
        if !validToAddress {
            isValidForm = false
            return isValidForm
        }
        if !tx.coin.isNativeToken {
            do {
                let evmToken = try await blockchainService.fetchSpecific(tx: tx)
                let (hasEnoughFees, feeErrorMsg) = await tx.hasEnoughNativeTokensToPayTheFees(specific: evmToken)
                if !hasEnoughFees {
                    errorTitle = "error"
                    errorMessage = feeErrorMsg
                    showAlert = true
                    logger.log("\(feeErrorMsg)")
                    isValidForm = false
                }
            } catch {
                let fetchErrorMsg = "Failed to fetch specific token data: \(tx.coin.ticker)"
                logger.log("\(fetchErrorMsg)")
                errorTitle = "error"
                errorMessage = fetchErrorMsg
                showAlert = true
                isValidForm = false
            }
        }
        
        // Cardano-specific validation: Check minimum UTXO value for amount and remaining balance
        if tx.coin.chain == .cardano && !tx.sendMaxAmount {
            let amountInLovelaces = tx.amountInRaw
            let totalBalance = tx.coin.rawBalance
            let estimatedFee = tx.fee
            
            let validation = CardanoHelper.validateUTXORequirements(
                sendAmount: amountInLovelaces,
                totalBalance: totalBalance.toBigInt(),
                estimatedFee: estimatedFee
            )
            
            if !validation.isValid {
                errorTitle = "error"
                errorMessage = validation.errorMessage ?? "Cardano UTXO validation failed"
                showAlert = true
                logger.log("Cardano UTXO validation failed: \(validation.errorMessage ?? "Unknown error")")
                isValidForm = false
            }
        }
        
        // DOT-specific validation: Check existential deposit (1 DOT minimum balance)
        if tx.coin.chain == .polkadot {
            let totalBalance = BigInt(tx.coin.rawBalance) ?? BigInt.zero
            let totalTransactionCost = tx.amountInRaw + tx.gas
            let remainingBalance = totalBalance - totalTransactionCost
            
            // Allow transaction only if:
            // 1. Remaining balance stays above 1 DOT, OR
            // 2. It's a complete MAX send (sendMaxAmount = true) that drains the entire balance
            if !tx.sendMaxAmount && remainingBalance < PolkadotHelper.defaultExistentialDeposit && remainingBalance > 0 {
                errorTitle = "error"
                errorMessage = "Keep account balance above 1 DOT. The remaining funds will be lost if balance is below 1 DOT"
                showAlert = true
                logger.log("DOT transaction would leave balance below existential deposit")
                isValidForm = false
            }
        }
        
        isLoading = false
        return isValidForm
    }
    
    func validateToAddress(tx: SendTransaction) async -> Bool {
        resetStates()
        
        guard !tx.toAddress.isEmpty else {
            errorTitle = "invalidAddress"
            errorMessage = "emptyAddressField"
            showAddressAlert = true
            logger.log("Empty address field.")
            isValidForm = false
            isLoading = false
            return false
        }
        
        do {
            tx.toAddress = try await AddressService.resolveInput(tx.toAddress, chain: tx.coin.chain)
            isNamespaceResolved = true
        } catch {
            errorTitle = "error"
            errorMessage = "validAddressDomainError"
            showAddressAlert = true
            logger.log("Please enter a valid address for the selected blockchain.")
            
            isValidForm = false
            isLoading = false
            return false
        }
        
        // Validate the "To" address
        if !isValidAddress && !isNamespaceResolved {
            errorTitle = "error"
            errorMessage = "validAddressError"
            showAddressAlert = true
            logger.log("Invalid address.")
            isValidForm = false
            return false
        }
        
        isLoading = false
        return true
    }
    
    func setHash(_ hash: String) {
        self.hash = hash
    }
    
    func stopMediator() {
        self.mediator.stop()
        logger.info("mediator server stopped.")
    }
    
    func feesInReadable(tx: SendTransaction, vault: Vault) -> String {
        guard let nativeCoin = vault.nativeCoin(for: tx.coin) else { return .empty }
        let fee = nativeCoin.decimal(for: tx.fee)
        // Use fee-specific formatting with more decimal places (5 instead of 2)
        return RateProvider.shared.fiatFeeString(value: fee, coin: nativeCoin)
    }
    
    func pickerCoins(vault: Vault, tx: SendTransaction) -> [Coin] {
        return vault.coins.sorted(by: {
            Int($0.chain == tx.coin.chain) > Int($1.chain == tx.coin.chain)
        })
    }
    
    private func resetStates() {
        errorTitle = ""
        errorMessage = ""
        isValidForm = true
        isNamespaceResolved = false
        isLoading = true
        showAddressAlert = false
        showAmountAlert = false
        showAlert = false
    }
    
    /// Check if there are pending Cosmos transactions that could cause nonce conflicts
    private func hasPendingCosmosTransactions(tx: SendTransaction) async -> Bool {
        // Only check for chains that support pending transaction tracking
        guard tx.coin.chain.supportsPendingTransactions else {
            // For non-Cosmos chains, immediately enable button
            hasPendingTransaction = false
            pendingTransactionCountdown = 0
            isCheckingPendingTransactions = false
            return false
        }
        
        // Set checking state to prevent button flickering
        isCheckingPendingTransactions = true
        
        let pendingTxManager = PendingTransactionManager.shared
        
        // Check for pending transactions (polling takes care of status updates)
        if pendingTxManager.hasPendingTransactions(for: tx.coin.address, chain: tx.coin.chain) {
            // Get the oldest pending transaction for user feedback
            if let oldestPending = pendingTxManager.getOldestPendingTransaction(for: tx.coin.address, chain: tx.coin.chain) {
                let elapsedSeconds = pendingTxManager.getElapsedSeconds(for: oldestPending)
                hasPendingTransaction = true
                pendingTransactionCountdown = elapsedSeconds
                isCheckingPendingTransactions = false
                isValidForm = false
                isLoading = false
                return true
            }
        }
        
        // No pending transactions
        hasPendingTransaction = false
        pendingTransactionCountdown = 0
        isCheckingPendingTransactions = false
        
        return false
    }
    
    private func calculatePlanFee(tx: SendTransaction, chainSpecific: BlockChainSpecific) async throws -> BigInt {
        guard let vault = ApplicationState.shared.currentVault else {
            throw HelperError.runtimeError("No vault available for plan fee calculation")
        }
        
        // Don't calculate plan fee if amount is 0 or empty
        let actualAmount = tx.amountInRaw
        if actualAmount == 0 {
            throw HelperError.runtimeError("Enter an amount to calculate accurate fees")
        }
        
        // For UTXO chains, force fresh UTXO fetch for fee calculation to avoid stale cache
        if tx.coin.chainType == .UTXO {
            await BlockchairService.shared.clearUTXOCache(for: tx.coin)
            let _ = try await BlockchairService.shared.fetchBlockchairData(coin: tx.coin)
        }
        
        let keysignFactory = KeysignPayloadFactory()
        let keysignPayload = try await keysignFactory.buildTransfer(
            coin: tx.coin,
            toAddress: tx.toAddress.isEmpty ? tx.coin.address : tx.toAddress,
            amount: actualAmount,
            memo: tx.memo.isEmpty ? nil : tx.memo,
            chainSpecific: chainSpecific,
            swapPayload: nil,
            vault: vault
        )
        
        let planFee: BigInt
        
        switch tx.coin.chain {
        case .cardano:
            guard let cardanoHelper = CardanoHelper.getHelper(vault: vault, coin: tx.coin) else {
                throw HelperError.runtimeError("Cardano helper not available")
            }
            planFee = try cardanoHelper.calculateDynamicFee(keysignPayload: keysignPayload)
            
        default: // UTXO chains
            guard let utxoHelper = UTXOChainsHelper.getHelper(vault: vault, coin: tx.coin) else {
                throw HelperError.runtimeError("UTXO helper not available for \(tx.coin.chain.name)")
            }
            let plan = try utxoHelper.getBitcoinTransactionPlan(keysignPayload: keysignPayload)
            planFee = BigInt(plan.fee)
        }
        
        // WalletCore must return valid fee
        if planFee > 0 {
            return planFee
        }
                
        // If WalletCore returns 0, it means insufficient balance
        // Return 0 and let the form validation handle it via tx.isAmountExceeded
        return BigInt.zero
    }
    
    /// Recalculate plan-based fees when amount changes (UTXO and Cardano chains)
    func recalculatePlanFeesIfNeeded(tx: SendTransaction) {
        guard (tx.coin.chainType == .UTXO || tx.coin.chain == .cardano) && tx.amountInRaw > 0 else { 
            return 
        }
        
        Task {
            await MainActor.run {
                tx.isCalculatingFee = true
            }
            
            do {
                let specific = try await blockchainService.fetchSpecific(tx: tx)
                let newFee = try await calculatePlanFee(tx: tx, chainSpecific: specific)
                
                await MainActor.run {
                    tx.fee = newFee
                    tx.isCalculatingFee = false
                }
            } catch {
                await MainActor.run {
                    tx.isCalculatingFee = false
                }
                print("Failed to recalculate plan fee for \(tx.coin.chain.name): \(error.localizedDescription)")
            }
        }
    }
}
