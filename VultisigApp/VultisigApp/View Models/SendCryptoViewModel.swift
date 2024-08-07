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
    @Published var showAlert = false
    @Published var currentIndex = 1
    @Published var currentTitle = "send"
    @Published var priceRate = 0.0
    @Published var coinBalance: String = "0"
    @Published var errorMessage = ""
    @Published var hash: String? = nil
    @Published var thor = ThorchainService.shared
    @Published var sol: SolanaService = SolanaService.shared
    @Published var sui: SuiService = SuiService.shared
    @Published var cryptoPrice = CryptoPriceService.shared
    @Published var utxo = BlockchairService.shared
    let maya = MayachainService.shared
    let atom = GaiaService.shared
    let kujira = KujiraService.shared
    let blockchainService = BlockChainService.shared
    
    private let mediator = Mediator.shared
    
    let totalViews = 5
    let titles = ["send", "verify", "send", "keysign", "done"]
    
    let logger = Logger(subsystem: "send-input-details", category: "transaction")
    
    func loadGasInfoForSending(tx: SendTransaction) async{
        do {
            let chainSpecific = try await blockchainService.fetchSpecific(for: tx.coin, sendMaxAmount: false, isDeposit: tx.isDeposit, transactionType: tx.transactionType)
            tx.gas = chainSpecific.gas.description
        } catch {
            print("error fetching data: \(error.localizedDescription)")
        }
    }
    
    func setMaxValues(tx: SendTransaction, percentage: Double = 100)  {
        let coinName = tx.coin.chain.name.lowercased()
        let key: String = "\(tx.fromAddress)-\(coinName)"
        isLoading = true
        switch tx.coin.chain {
        case .bitcoin,.dogecoin,.litecoin,.bitcoinCash,.dash:
            tx.sendMaxAmount = percentage == 100 // Never set this to true if the percentage is not 100, otherwise it will wipe your wallet.
            tx.amount = utxo.blockchairData.get(key)?.address?.balanceInBTC ?? "0.0"
            setPercentageAmount(tx: tx, for: percentage)
            Task{
                await convertToFiat(newValue: tx.amount, tx: tx, setMaxValue: true)
                isLoading = false
            }
        case .ethereum, .avalanche, .bscChain, .arbitrum, .base, .optimism, .polygon, .blast, .cronosChain, .zksync:
            Task {
                do {
                    if tx.coin.isNativeToken {
                        let evm = try await blockchainService.fetchSpecific(for: tx.coin, sendMaxAmount: true, isDeposit: tx.isDeposit, transactionType: tx.transactionType)
                        let totalFeeWei = evm.fee
                        tx.amount = "\(tx.coin.getMaxValue(totalFeeWei))" // the decimals must be truncaded otherwise the give us precisions errors
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
                
                await convertToFiat(newValue: tx.amount, tx: tx)
                isLoading = false
            }
            
        case .solana:
            Task {
                do{
                    if tx.coin.isNativeToken {
                        let rawBalance = try await sol.getSolanaBalance(coin: tx.coin)
                        tx.coin.rawBalance = rawBalance
                        tx.amount = "\(tx.coin.getMaxValue(SolanaHelper.defaultFeeInLamports))"
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
                
                await convertToFiat(newValue: tx.amount, tx: tx)
                isLoading = false
            }
        case .sui:
            Task {
                do {
                    let rawBalance = try await sui.getBalance(coin: tx.coin)
                    tx.coin.rawBalance = rawBalance
                    
                    var gas = BigInt.zero
                    if percentage == 100 {
                        gas = tx.coin.feeDefault.toBigInt()
                    }
                    
                    tx.amount = "\(tx.coin.getMaxValue(gas))"
                    setPercentageAmount(tx: tx, for: percentage)
                    
                    await convertToFiat(newValue: tx.amount, tx: tx)
                } catch {
                    print("fail to load solana balances,error:\(error.localizedDescription)")
                }
                
                isLoading = false
            }
        case .kujira, .gaiaChain, .mayaChain, .thorChain, .polkadot, .dydx:
            Task {
                await BalanceService.shared.updateBalance(for: tx.coin)
                
                var gas = BigInt.zero
                
                if percentage == 100 {
                    gas = BigInt(tx.gasDecimal.description,radix:10) ?? 0
                }
                
                tx.amount = "\(tx.coin.getMaxValue(gas))"
                setPercentageAmount(tx: tx, for: percentage)
                
                await convertToFiat(newValue: tx.amount, tx: tx)
                
                isLoading = false
            }
        }
    }
    
    private func setPercentageAmount(tx: SendTransaction, for percentage: Double) {
        let max = tx.amount
        let multiplier = (Decimal(percentage) / 100)
        let amountDecimal = (Decimal(string: max) ?? 0) * multiplier
        tx.amount = "\(amountDecimal)"
    }
    
    func convertFiatToCoin(newValue: String, tx: SendTransaction) async {
        if let newValueDecimal = Decimal(string: newValue) {
            let newValueCoin = newValueDecimal / Decimal(tx.coin.price)
            let truncatedValueCoin = newValueCoin.truncated(toPlaces: tx.coin.decimals)
            tx.amount = NSDecimalNumber(decimal: truncatedValueCoin).stringValue
            tx.sendMaxAmount = false
        } else {
            tx.amount = ""
        }
    }
    
    func convertToFiat(newValue: String, tx: SendTransaction, setMaxValue: Bool = false) async {
        if let newValueDecimal = Decimal(string: newValue) {
            let newValueFiat = newValueDecimal * Decimal(tx.coin.price)
            let truncatedValueFiat = newValueFiat.truncated(toPlaces: 2) // Assuming 2 decimal places for fiat
            tx.amountInFiat = NSDecimalNumber(decimal: truncatedValueFiat).stringValue
            tx.sendMaxAmount = setMaxValue
        } else {
            tx.amountInFiat = ""
        }
    }
    
    func validateAddress(tx: SendTransaction, address: String) {
        isValidAddress = AddressService.validateAddress(address: address, chain: tx.coin.chain)
    }
    
    func validateForm(tx: SendTransaction) async -> Bool {
        // Reset validation state at the beginning
        errorMessage = ""
        isValidForm = true
        
        // Validate the "To" address
        if !isValidAddress {
            errorMessage = "validAddressError"
            showAlert = true
            logger.log("Invalid address.")
            isValidForm = false
        }
        
        if tx.toAddress.isNameService() {
            let resolvedAddress = await AddressService.resolveDomaninAddress(address: tx.toAddress, chain: tx.coin.chain)
            // it means it didnt resolve it
            if resolvedAddress == tx.toAddress {
                errorMessage = "validAddressDomainError"
                showAlert = true
                logger.log("We were unable to resolve the address of this domain service on this chain.")
                isValidForm = false
                return isValidForm
            }
            
            // Set the HEX address to send directly
            tx.toAddress = resolvedAddress
        }
        
        let amount = tx.amountDecimal
        let gasFee = tx.gasDecimal
        
        if amount <= 0 {
            errorMessage = "positiveAmountError"
            showAlert = true
            logger.log("Invalid or non-positive amount.")
            isValidForm = false
            return isValidForm
        }
        
        if gasFee <= 0 {
            errorMessage = "nonNegativeFeeError"
            showAlert = true
            logger.log("Invalid or negative fee.")
            isValidForm = false
            return isValidForm
        }
        
        if tx.isAmountExceeded {
            
            errorMessage = "walletBalanceExceededError"
            showAlert = true
            logger.log("Total transaction cost exceeds wallet balance.")
            isValidForm = false
            
        }
        
        if !tx.coin.isNativeToken {
            do {
                let evmToken = try await blockchainService.fetchSpecific(for: tx.coin, sendMaxAmount: tx.sendMaxAmount, isDeposit: tx.isDeposit, transactionType: tx.transactionType)
                let (hasEnoughFees, feeErrorMsg) = await tx.hasEnoughNativeTokensToPayTheFees(specific: evmToken)
                if !hasEnoughFees {
                    errorMessage = feeErrorMsg
                    showAlert = true
                    logger.log("\(feeErrorMsg)")
                    isValidForm = false
                }
            } catch {
                let fetchErrorMsg = "Failed to fetch specific token data: \(tx.coin.ticker)"
                logger.log("\(fetchErrorMsg)")
                errorMessage = fetchErrorMsg
                showAlert = true
                isValidForm = false
            }
        }
        
        return isValidForm
    }
    
    func setHash(_ hash: String) {
        self.hash = hash
    }
    
    func moveToNextView() {
        currentIndex += 1
        currentTitle = titles[currentIndex-1]
    }
    
    func getProgress() -> Double {
        Double(currentIndex)/Double(totalViews)
    }
    
    func stopMediator() {
        self.mediator.stop()
        logger.info("mediator server stopped.")
    }
    
    private func getTransactionPlan(tx: SendTransaction, key:String) -> TW_Bitcoin_Proto_TransactionPlan? {
        guard let utxoInfo = utxo.blockchairData.get(key)?.selectUTXOsForPayment().map({
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
            chainSpecific: BlockChainSpecific.UTXO(byteFee: tx.gas.toBigInt(), sendMaxAmount: tx.sendMaxAmount),
            utxos: utxoInfo,
            memo: tx.memo,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: vault.pubKeyECDSA,
            vaultLocalPartyID: vault.localPartyID
        )
        
        guard let helper = UTXOChainsHelper.getHelper(vault: vault, coin: tx.coin) else {
            return nil
        }
        
        return try? helper.getBitcoinTransactionPlan(keysignPayload: keysignPayload)
    }
    
    func handleBackTap() {
        currentIndex-=1
        currentTitle = titles[currentIndex-1]
    }
}
