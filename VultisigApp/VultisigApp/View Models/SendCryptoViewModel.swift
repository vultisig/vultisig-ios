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
    @Published var errorMessage: String?
    @Published var hash: String? = nil
    @Published var approveHash: String? = nil
    
    // Logic delegation
    private let logic = SendCryptoLogic()
    
    // State for alerts
    @Published var showAddressAlert: Bool = false
    @Published var showAmountAlert: Bool = false
    
    // State for pending transactions
    @Published var hasPendingTransaction: Bool = false
    @Published var pendingTransactionCountdown: Int = 0
    @Published var isCheckingPendingTransactions: Bool = false
    
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
        
        if let info = await logic.loadGasInfoForSending(tx: tx) {
            tx.gas = info.gas
            tx.fee = info.fee
            if let gasLimit = info.gasLimit {
                tx.estematedGasLimit = gasLimit
            }
        }
    }
    
    func loadFastVault(tx: SendTransaction, vault: Vault) async {
        tx.isFastVault = await logic.loadFastVault(tx: tx, vault: vault)
    }
    
    func setMaxValues(tx: SendTransaction, percentage: Double = 100) {
        errorMessage = ""
        isLoading = true
        
        Task {
            await logic.setMaxValues(tx: tx, percentage: percentage)
            isLoading = false
        }
    }
    
    func convertFiatToCoin(newValue: String, tx: SendTransaction) {
        logic.convertFiatToCoin(newValue: newValue, tx: tx)
    }
    
    func convertToFiat(newValue: String, tx: SendTransaction, setMaxValue: Bool = false) {
        logic.convertToFiat(newValue: newValue, tx: tx, setMaxValue: setMaxValue)
    }
    
    func validateAddress(tx: SendTransaction, address: String) {
        guard !isNamespaceResolved else {
            isValidAddress = true
            return
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
        resetStates()
        
        let result = await logic.validateForm(tx: tx, hasPendingTransaction: hasPendingTransaction)
        
        isValidForm = result.isValid
        errorTitle = result.errorTitle
        errorMessage = result.errorMessage
        showAlert = result.showAlert
        showAmountAlert = result.showAmountAlert
        showAddressAlert = result.showAddressAlert
        
        isLoading = false
        return isValidForm
    }
    
    func validateToAddress(tx: SendTransaction) async -> Bool {
        resetStates()
        
        let result = await logic.validateToAddress(tx: tx)
        
        if result.isValid {
            isNamespaceResolved = true
        } else {
             errorTitle = result.errorTitle
             errorMessage = result.errorMessage
             showAddressAlert = result.showAddressAlert
             isValidForm = false
        }
        
        isLoading = false
        return result.isValid
    }
    
    func setHash(_ hash: String) {
        self.hash = hash
    }
    
    func stopMediator() {
        Mediator.shared.stop()
        logger.info("mediator server stopped.")
    }
    
    func feesInReadable(tx: SendTransaction, vault: Vault) -> String {
        guard let nativeCoin = vault.nativeCoin(for: tx.coin) else { return .empty }
        let fee = nativeCoin.decimal(for: tx.fee)
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
}

// MARK: - SendCryptoLogic (Business Logic Struct)

struct SendCryptoLogic {
    
    private let logger = Logger(subsystem: "send-crypto-logic", category: "transaction")
    private let blockchainService = BlockChainService.shared
    private let mediator = Mediator.shared
    private let fastVaultService = FastVaultService.shared
    
    // Services
    private let sol = SolanaService.shared
    private let sui = SuiService.shared
    private let ton = TonService.shared
    private let utxo = BlockchairService.shared
    private let ripple = RippleService.shared
    private let tron = TronService.shared
    private let balanceService = BalanceService.shared
    
    struct ValidationResult {
        var isValid: Bool
        var errorTitle: String = ""
        var errorMessage: String? = nil
        var showAlert: Bool = false
        var showAmountAlert: Bool = false
        var showAddressAlert: Bool = false
    }
    
    func loadGasInfoForSending(tx: SendTransaction) async -> (gas: BigInt, fee: BigInt, gasLimit: BigInt?)? {
        do {
            let specific = try await blockchainService.fetchSpecific(tx: tx)
            let gas = specific.gas
            var fee = specific.fee
            
            // For UTXO and Cardano chains, calculate actual total fee using WalletCore plan.fee (like Android)
            if tx.coin.chainType == .UTXO || tx.coin.chainType == .Cardano {
                if tx.amountInRaw > 0 {
                    // Only calculate accurate fee when user has entered an amount
                    fee = try await calculateUTXOPlanFee(tx: tx, chainSpecific: specific)
                } else {
                    // Initial state - no amount yet, use 0 to indicate fee not calculated yet
                    fee = BigInt.zero
                }
            }
            
            return (gas: gas, fee: fee, gasLimit: specific.gasLimit)
        } catch {
            print("error fetching data: \(error.localizedDescription)")
            return nil
        }
    }
    
    func loadFastVault(tx: SendTransaction, vault: Vault) async -> Bool {
        let isExist = await fastVaultService.exist(pubKeyECDSA: vault.pubKeyECDSA)
        let isLocalBackup = vault.localPartyID.lowercased().contains("server-")
        
        return isExist && !isLocalBackup
    }
    
    func calculateUTXOPlanFee(tx: SendTransaction, chainSpecific: BlockChainSpecific) async throws -> BigInt {
        guard let vault = AppViewModel.shared.selectedVault else {
            throw HelperError.runtimeError("No vault available for UTXO fee calculation")
        }
        
        // Don't calculate plan fee if amount is 0 or empty
        let actualAmount = tx.amountInRaw
        if actualAmount == 0 {
            throw HelperError.runtimeError("Enter an amount to calculate accurate UTXO fees")
        }
        
        // Force fresh UTXO fetch for fee calculation to avoid stale cache
        await BlockchairService.shared.clearUTXOCache(for: tx.coin)
        
        // Fetch fresh UTXOs from API
        let _ = try await BlockchairService.shared.fetchBlockchairData(coin: tx.coin)
        
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
            let cardanoHelper = CardanoHelper()
            planFee = try cardanoHelper.calculateDynamicFee(keysignPayload: keysignPayload)
            
        default: // UTXO chains
            guard let utxoHelper = UTXOChainsHelper.getHelper(coin: tx.coin) else {
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
    
    func validateForm(tx: SendTransaction, hasPendingTransaction: Bool) async -> ValidationResult {
        var result = ValidationResult(isValid: true)
        
        // Check for pending Cosmos transactions that could cause nonce conflicts
        if hasPendingTransaction && tx.coin.chain.supportsPendingTransactions {
             result.isValid = false
             return result
        }
        
        let amount = tx.amountDecimal
        let gasFee = tx.gasDecimal
        
        if amount <= 0 {
            result.errorTitle = "error"
            result.errorMessage = "positiveAmountError"
            result.showAmountAlert = true
            logger.log("Invalid or non-positive amount.")
            result.isValid = false
            return result
        }
        
        if gasFee == 0 && !tx.coin.allowZeroGas() {
            result.errorTitle = "error"
            result.errorMessage = "noGasEstimation"
            result.showAmountAlert = true
            logger.log("No gas estimation.")
            result.isValid = false
            return result
        }
        
        if gasFee < 0 {
            result.errorTitle = "error"
            result.errorMessage = "nonNegativeFeeError"
            result.showAmountAlert = true
            logger.log("Invalid or negative fee.")
            result.isValid = false
            return result
        }
        
        if tx.isAmountExceeded {
            result.errorTitle = "error"
            result.errorMessage = "walletBalanceExceededError"
            result.showAmountAlert = true
            logger.log("Total transaction cost exceeds wallet balance.")
            result.isValid = false
            return result
        }
        
        // check UTXO minimum amount and fee validation
        if tx.coin.chainType == .UTXO {
            let dustThreshold = tx.coin.coinType.getFixedDustThreshold()
            if tx.amountInRaw < dustThreshold {
                result.errorTitle = "error"
                result.errorMessage = "amount is below the dust threshold."
                result.showAmountAlert = true
                result.isValid = false
                return result
            }
            
            // Check if WalletCore returned 0 fee (insufficient balance for UTXO transaction)
            if tx.fee == 0 && tx.amountInRaw > 0 {
                result.errorTitle = "error"
                result.errorMessage = "walletBalanceExceededError"
                result.showAmountAlert = true
                logger.log("Insufficient UTXO balance to cover transaction and fees.")
                result.isValid = false
                return result
            }
        }
        
        // Validate To Address
        let validToAddress = await validateToAddress(tx: tx)
        if !validToAddress.isValid {
            result.errorTitle = validToAddress.errorTitle
            result.errorMessage = validToAddress.errorMessage
            result.showAddressAlert = validToAddress.showAddressAlert
            result.isValid = false
            return result
        }
        
        if !tx.coin.isNativeToken {
            do {
                let evmToken = try await blockchainService.fetchSpecific(tx: tx)
                let (hasEnoughFees, feeErrorMsg) = await tx.hasEnoughNativeTokensToPayTheFees(specific: evmToken)
                if !hasEnoughFees {
                    result.errorTitle = "error"
                    result.errorMessage = feeErrorMsg
                    result.showAlert = true
                    logger.log("\(feeErrorMsg)")
                    result.isValid = false
                }
            } catch {
                let fetchErrorMsg = "Failed to fetch specific token data: \(tx.coin.ticker)"
                logger.log("\(fetchErrorMsg)")
                result.errorTitle = "error"
                result.errorMessage = fetchErrorMsg
                result.showAlert = true
                result.isValid = false
            }
        }
        
        // Cardano-specific validation
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
                result.errorTitle = "error"
                result.errorMessage = validation.errorMessage ?? "Cardano UTXO validation failed"
                result.showAlert = true
                logger.log("Cardano UTXO validation failed: \(validation.errorMessage ?? "Unknown error")")
                result.isValid = false
            }
        }
        
        // DOT-specific validation
        if tx.coin.chain == .polkadot {
            let totalBalance = BigInt(tx.coin.rawBalance) ?? BigInt.zero
            let totalTransactionCost = tx.amountInRaw + tx.gas
            let remainingBalance = totalBalance - totalTransactionCost
            
            if !tx.sendMaxAmount && remainingBalance < PolkadotHelper.defaultExistentialDeposit && remainingBalance > 0 {
                result.errorTitle = "error"
                result.errorMessage = "Keep account balance above 1 DOT. The remaining funds will be lost if balance is below 1 DOT"
                result.showAlert = true
                logger.log("DOT transaction would leave balance below existential deposit")
                result.isValid = false
            }
        }
        
        return result
    }
    
    func validateToAddress(tx: SendTransaction) async -> ValidationResult {
        var result = ValidationResult(isValid: true)
        
        guard !tx.toAddress.isEmpty else {
            result.errorTitle = "invalidAddress"
            result.errorMessage = "emptyAddressField"
            result.showAddressAlert = true
            logger.log("Empty address field.")
            result.isValid = false
            return result
        }
        
        do {
            let resolvedAddress = try await AddressService.resolveInput(tx.toAddress, chain: tx.coin.chain)
            // Mutate tx address on MainActor
            await MainActor.run {
                tx.toAddress = resolvedAddress
            }
        } catch {
            result.errorTitle = "error"
            result.errorMessage = "validAddressDomainError"
            result.showAddressAlert = true
            logger.log("Please enter a valid address for the selected blockchain.")
            result.isValid = false
            return result
        }
        
        let isValid = AddressService.validateAddress(address: tx.toAddress, chain: tx.coin.chain)
        if !isValid {
             result.errorTitle = "error"
             result.errorMessage = "validAddressError"
             result.showAddressAlert = true
             logger.log("Invalid address.")
             result.isValid = false
             return result
        }
        
        return result
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
            let truncatedValueFiat = newValueFiat.truncated(toPlaces: 2)
            tx.amountInFiat = truncatedValueFiat.formatToDecimal(digits: tx.coin.decimals)
            tx.sendMaxAmount = setMaxValue
            
            // Recalculate UTXO-based fees when amount changes
            recalculateUTXOFeesIfNeeded(tx: tx)
        } else {
            tx.amountInFiat = ""
        }
    }
    
    func recalculateUTXOFeesIfNeeded(tx: SendTransaction) {
        guard (tx.coin.chainType == .UTXO || tx.coin.chainType == .Cardano) && tx.amountInRaw > 0 else { 
            return 
        }
        
        Task {
            await MainActor.run {
                tx.isCalculatingFee = true
            }
            
            do {
                let specific = try await blockchainService.fetchSpecific(tx: tx)
                let newFee = try await calculateUTXOPlanFee(tx: tx, chainSpecific: specific)
                
                await MainActor.run {
                    tx.fee = newFee
                    tx.isCalculatingFee = false
                }
            } catch {
                await MainActor.run {
                    tx.isCalculatingFee = false
                }
                print("Failed to recalculate UTXO fee: \(error.localizedDescription)")
            }
        }
    }
    
    func setMaxValues(tx: SendTransaction, percentage: Double = 100) async {
        let coinName = tx.coin.chain.name.lowercased()
        let key: String = "\(tx.fromAddress)-\(coinName)"
        
        switch tx.coin.chain {
        case .bitcoin,.dogecoin,.litecoin,.bitcoinCash,.dash, .zcash:
            await MainActor.run { tx.sendMaxAmount = percentage == 100 }
            let amount = await utxo.getByKey(key: key)?.address?.balanceInBTC ?? "0.0"
            await MainActor.run { tx.amount = amount }
            await MainActor.run { setPercentageAmount(tx: tx, for: percentage) }
            await MainActor.run { convertToFiat(newValue: tx.amount, tx: tx, setMaxValue: tx.sendMaxAmount) }
            
        case .cardano:
            await MainActor.run { tx.sendMaxAmount = percentage == 100 }
            await balanceService.updateBalance(for: tx.coin)
            
            let gas = BigInt.zero
            let maxDecimals = tx.coin.decimals > 0 ? tx.coin.decimals - 1 : tx.coin.decimals
            let amount = "\(tx.coin.getMaxValue(gas).formatToDecimal(digits: maxDecimals))"
            await MainActor.run { tx.amount = amount }
            await MainActor.run { setPercentageAmount(tx: tx, for: percentage) }
            await MainActor.run { convertToFiat(newValue: tx.amount, tx: tx, setMaxValue: tx.sendMaxAmount) }
            
        case .ethereum, .avalanche, .bscChain, .arbitrum, .base, .optimism, .polygon, .polygonV2, .blast, .cronosChain, .zksync,.ethereumSepolia, .mantle, .hyperliquid, .sei:
            do {
                if tx.coin.isNativeToken {
                    let evm = try await blockchainService.fetchSpecific(tx: tx)
                    let totalFeeWei = evm.fee
                    await MainActor.run {
                        tx.amount = "\(tx.coin.getMaxValue(totalFeeWei).formatToDecimal(digits: tx.coin.decimals))"
                        setPercentageAmount(tx: tx, for: percentage)
                    }
                } else {
                    await MainActor.run {
                        tx.amount = "\(tx.coin.getMaxValue(0))"
                        setPercentageAmount(tx: tx, for: percentage)
                    }
                }
            } catch {
                await MainActor.run {
                    tx.amount = "\(tx.coin.getMaxValue(0))"
                    setPercentageAmount(tx: tx, for: percentage)
                }
                print("Failed to get EVM balance, error: \(error.localizedDescription)")
            }
            await MainActor.run { convertToFiat(newValue: tx.amount, tx: tx) }
            
        case .solana:
            do{
                if tx.coin.isNativeToken {
                    let rawBalance = try await sol.getSolanaBalance(coin: tx.coin)
                    await MainActor.run {
                        tx.coin.rawBalance = rawBalance
                        tx.amount = "\(tx.coin.getMaxValue(SolanaHelper.defaultFeeInLamports).formatToDecimal(digits: tx.coin.decimals))"
                        setPercentageAmount(tx: tx, for: percentage)
                    }
                } else {
                    await MainActor.run {
                        tx.amount = "\(tx.coin.getMaxValue(0))"
                        setPercentageAmount(tx: tx, for: percentage)
                    }
                }
            } catch {
                await MainActor.run {
                    tx.amount = "\(tx.coin.getMaxValue(0))"
                    setPercentageAmount(tx: tx, for: percentage)
                }
                print("Failed to get SOLANA balance, error: \(error.localizedDescription)")
            }
            await MainActor.run { convertToFiat(newValue: tx.amount, tx: tx) }
            
        case .sui:
            do {
                let rawBalance = try await sui.getBalance(coin: tx.coin)
                await MainActor.run { tx.coin.rawBalance = rawBalance }
                
                if tx.coin.isNativeToken {
                    var gas = BigInt.zero
                    
                    if percentage == 100 {
                        let originalAmount = tx.amount
                        let maxAmount = tx.coin.rawBalance.toBigInt(decimals: tx.coin.decimals)
                        let maxDecimal = Decimal(maxAmount) / pow(10, tx.coin.decimals)
                        await MainActor.run {
                            tx.amount = "\(maxDecimal.formatToDecimal(digits: tx.coin.decimals))"
                            tx.sendMaxAmount = true
                        }
                        
                        do {
                            let chainSpecific = try await blockchainService.fetchSpecific(tx: tx)
                            if case .Sui(_, _, let gasBudget) = chainSpecific {
                                gas = gasBudget
                            }
                        } catch {
                            print("⚠️ Sui dynamic fee calculation failed, using default: \(error.localizedDescription)")
                            gas = (BigInt(3000000) * 115) / 100
                        }
                        
                        await MainActor.run {
                            tx.sendMaxAmount = false
                            tx.amount = originalAmount
                        }
                    }
                    
                    await MainActor.run {
                        tx.amount = "\(tx.coin.getMaxValue(gas).formatToDecimal(digits: tx.coin.decimals))"
                        setPercentageAmount(tx: tx, for: percentage)
                        convertToFiat(newValue: tx.amount, tx: tx)
                    }
                } else {
                    await MainActor.run {
                        tx.amount = "\(tx.coin.getMaxValue(0))"
                        setPercentageAmount(tx: tx, for: percentage)
                    }
                }
            } catch {
                print("⚠️ Failed to load Sui balance: \(error.localizedDescription)")
            }
            
        case .kujira, .gaiaChain, .mayaChain, .thorChain, .thorChainStagenet, .dydx, .osmosis, .terra, .terraClassic, .noble, .akash:
            await balanceService.updateBalance(for: tx.coin)
            
            var gas = BigInt.zero
            if percentage == 100 && tx.coin.isNativeToken {
                gas = BigInt(tx.gasDecimal.description,radix:10) ?? 0
            }
            
            await MainActor.run {
                tx.amount = "\(tx.coin.getMaxValue(gas).formatToDecimal(digits: tx.coin.decimals))"
                setPercentageAmount(tx: tx, for: percentage)
                convertToFiat(newValue: tx.amount, tx: tx)
            }
            
        case .polkadot:
            do {
                await MainActor.run { tx.sendMaxAmount = percentage == 100 }
                await balanceService.updateBalance(for: tx.coin)
                
                var gas = BigInt.zero
                let dot = try await blockchainService.fetchSpecific(tx: tx)
                gas = dot.gas
                
                await MainActor.run {
                    tx.amount = "\(tx.coin.getMaxValue(gas).formatToDecimal(digits: tx.coin.decimals))"
                    setPercentageAmount(tx: tx, for: percentage)
                    convertToFiat(newValue: tx.amount, tx: tx, setMaxValue: tx.sendMaxAmount)
                }
            } catch {
                await MainActor.run {
                    tx.amount = "\(tx.coin.getMaxValue(0))"
                    setPercentageAmount(tx: tx, for: percentage)
                    convertToFiat(newValue: tx.amount, tx: tx, setMaxValue: tx.sendMaxAmount)
                }
                print("Failed to get Polkadot dynamic fee, error: \(error.localizedDescription)")
            }
            
        case .ton:
            do {
                await MainActor.run { tx.sendMaxAmount = percentage == 100 }
                let rawBalance: String
                if tx.coin.isNativeToken {
                    rawBalance = try await ton.getBalance(tx.coin)
                } else {
                    rawBalance = try await ton.getJettonBalance(tx.coin)
                }

                await MainActor.run {
                    tx.coin.rawBalance = rawBalance
                    let gasForMax: BigInt = tx.coin.isNativeToken && percentage != 100 ? TonHelper.defaultFee : 0
                    tx.amount = "\(tx.coin.getMaxValue(gasForMax).formatToDecimal(digits: tx.coin.decimals))"
                    setPercentageAmount(tx: tx, for: percentage)
                    convertToFiat(newValue: tx.amount, tx: tx, setMaxValue: tx.sendMaxAmount)
                }
            } catch {
                print("fail to load ton balances,error:\(error.localizedDescription)")
            }

        case .ripple:
            do {
                let rawBalance = try await ripple.getBalance(tx.coin)
                await MainActor.run {
                    tx.coin.rawBalance = rawBalance
                    var gas = BigInt.zero
                    if percentage == 100 {
                        gas = tx.coin.feeDefault.toBigInt()
                    }
                    tx.amount = "\(tx.coin.getMaxValue(gas).formatToDecimal(digits: tx.coin.decimals))"
                    setPercentageAmount(tx: tx, for: percentage)
                    convertToFiat(newValue: tx.amount, tx: tx)
                }
            } catch {
                print("fail to load ripple balances,error:\(error.localizedDescription)")
            }
            
        case .tron:
            do {
                let rawBalance = try await tron.getBalance(coin: tx.coin)
                await MainActor.run {
                    tx.coin.rawBalance = rawBalance
                    var gas = BigInt.zero
                    if percentage == 100 {
                        gas = tx.coin.feeDefault.toBigInt()
                    }
                    tx.amount = "\(tx.coin.getMaxValue(gas).formatToDecimal(digits: tx.coin.decimals))"
                    setPercentageAmount(tx: tx, for: percentage)
                    convertToFiat(newValue: tx.amount, tx: tx)
                }
            } catch {
                print("fail to load TRON balances,error:\(error.localizedDescription)")
            }
        }
    }
    
    private func setPercentageAmount(tx: SendTransaction, for percentage: Double) {
        let max = tx.amount
        let multiplier = (Decimal(percentage) / 100)
        let amountDecimal = max.toDecimal() * multiplier
        tx.amount = amountDecimal.formatToDecimal(digits: tx.coin.decimals)
    }
}
