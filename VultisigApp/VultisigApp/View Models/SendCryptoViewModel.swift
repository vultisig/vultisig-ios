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
class SendCryptoViewModel: ObservableObject, TransferViewModel {
    @Published var isLoading = false
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
    
    let blockchainService = BlockChainService.shared
    
    private let mediator = Mediator.shared
    private let fastVaultService = FastVaultService.shared
    
    let totalViews = 5
    let titles = ["send", "verify", "pair", "keysign", "done"]
    
    let logger = Logger(subsystem: "send-input-details", category: "transaction")
    
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
            tx.fee = specific.fee
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
    func setMaxValues(tx: SendTransaction, percentage: Double = 100)  {
        let coinName = tx.coin.chain.name.lowercased()
        let key: String = "\(tx.fromAddress)-\(coinName)"
        isLoading = true
        switch tx.coin.chain {
        case .bitcoin,.dogecoin,.litecoin,.bitcoinCash,.dash, .zcash:
            tx.sendMaxAmount = percentage == 100 // Never set this to true if the percentage is not 100, otherwise it will wipe your wallet.
            tx.amount = utxo.blockchairData.get(key)?.address?.balanceInBTC ?? "0.0"
            setPercentageAmount(tx: tx, for: percentage)
            Task{
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
        case .ethereum, .avalanche, .bscChain, .arbitrum, .base, .optimism, .polygon, .polygonV2, .blast, .cronosChain, .zksync,.ethereumSepolia:
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
                    if percentage == 100 {
                        // For max sends, fetch actual gas estimation instead of using default fee
                        let polkadotSpecific = try await blockchainService.fetchSpecific(tx: tx)
                        gas = polkadotSpecific.gas
                    }
                    
                    tx.amount = "\(tx.coin.getMaxValue(gas).formatToDecimal(digits: tx.coin.decimals))"
                    setPercentageAmount(tx: tx, for: percentage)
                    
                    convertToFiat(newValue: tx.amount, tx: tx, setMaxValue: tx.sendMaxAmount)
                } catch {
                    // Fallback to default fee if gas estimation fails
                    await BalanceService.shared.updateBalance(for: tx.coin)
                    
                    var gas = BigInt.zero
                    if percentage == 100 {
                        gas = tx.coin.feeDefault.toBigInt()
                    }
                    
                    tx.amount = "\(tx.coin.getMaxValue(gas).formatToDecimal(digits: tx.coin.decimals))"
                    setPercentageAmount(tx: tx, for: percentage)
                    
                    convertToFiat(newValue: tx.amount, tx: tx, setMaxValue: tx.sendMaxAmount)
                    print("Failed to get DOT gas estimation, using default fee: \(error.localizedDescription)")
                }
                
                isLoading = false
            }
        case .ton:
            Task {
                do {
                    tx.sendMaxAmount = percentage == 100 // Never set this to true if the percentage is not 100, otherwise it will wipe your wallet.
                    let rawBalance = try await ton.getBalance(tx.coin)
                    tx.coin.rawBalance = rawBalance
                    
                    var gas = BigInt.zero
                    if percentage == 100 {
                        gas = tx.coin.feeDefault.toBigInt()
                    }
                    
                    tx.amount = "\(tx.coin.getMaxValue(gas).formatToDecimal(digits: tx.coin.decimals))"
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
        
        if gasFee == 0 {
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
    
    func moveToNextView() {
        currentIndex += 1
        currentTitle = titles[currentIndex-1]
    }
    
    func stopMediator() {
        self.mediator.stop()
        logger.info("mediator server stopped.")
    }
    
    func feesInReadable(tx: SendTransaction, vault: Vault) -> String {
        guard let nativeCoin = vault.nativeCoin(for: tx.coin) else { return .empty }
        let fee = nativeCoin.decimal(for: tx.fee)
        return RateProvider.shared.fiatBalanceString(value: fee, coin: nativeCoin)
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

    private func getTransactionPlan(tx: SendTransaction, key:String) -> TW_Bitcoin_Proto_TransactionPlan? {
        let totalAmount = tx.amountInRaw + BigInt(tx.gas * 1480)
        guard let utxoInfo = utxo.blockchairData
            .get(key)?.selectUTXOsForPayment(amountNeeded: Int64(totalAmount))
            .map({
                UtxoInfo(
                    hash: $0.transactionHash ?? "",
                    amount: Int64($0.value ?? 0),
                    index: UInt32($0.index ?? -1)
                )
            }), !utxoInfo.isEmpty else {
            return nil
        }
        
        let totalSelectedAmount = utxoInfo.reduce(0) { $0 + $1.amount }
        
        guard let vault = ApplicationState.shared.currentVault else {
            return nil
        }
        
        let keysignPayload = KeysignPayload(
            coin: tx.coin,
            toAddress: tx.toAddress,
            toAmount: BigInt(totalSelectedAmount),
            chainSpecific: BlockChainSpecific.UTXO(byteFee: tx.gas, sendMaxAmount: tx.sendMaxAmount),
            utxos: utxoInfo,
            memo: tx.memo,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: vault.pubKeyECDSA,
            vaultLocalPartyID: vault.localPartyID,
            libType: (vault.libType ?? .GG20).toString(),
            wasmExecuteContractPayload: nil,
            skipBroadcast: false
        )
        
        guard let helper = UTXOChainsHelper.getHelper(vault: vault, coin: tx.coin) else {
            return nil
        }
        
        return try? helper.getBitcoinTransactionPlan(keysignPayload: keysignPayload)
    }
    
    func handleBackTap(_ dismiss: DismissAction) {
        guard currentIndex>1 else {
            dismiss()
            return
        }
        
        currentIndex-=1
        currentTitle = titles[currentIndex-1]
    }
}
