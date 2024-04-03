//
//  SendCryptoDetailsViewModel.swift
//  VoltixApp
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
    @Published var cryptoPrice = CryptoPriceService.shared
    @Published var utxo = BlockchairService.shared
    @Published var avax = AvalancheService.shared
    
    private let eth = EtherScanService.shared
    private let bsc = BSCService.shared
    private let mediator = Mediator.shared
    
    let totalViews = 5
    let titles = ["send", "verify", "pair", "keysign", "done"]
    
    let logger = Logger(subsystem: "send-input-details", category: "transaction")
    
    func loadGasInfoForSending(tx: SendTransaction) async{
        do {
            if tx.coin.chain.chainType == ChainType.UTXO {
                let sats = try await utxo.fetchSatsPrice(coin: tx.coin)
                tx.gas = String(sats)
            } else if tx.coin.chain.name  == Chain.Ethereum.name  {
                print("The loadData for \(tx.coin.ticker)")
                let (gasPrice,priorityFee,nonce) = try await eth.getETHGasInfo(fromAddress: tx.fromAddress)
                tx.gas = gasPrice
                tx.nonce = nonce
                tx.priorityFeeGwei = priorityFee
                
            } else if tx.coin.chain.name  == Chain.BSCChain.name  {
                print("The loadData for \(tx.coin.ticker)")
                let (gasPrice,priorityFee,nonce) = try await bsc.getBscGasInfo(fromAddress: tx.fromAddress)
                tx.gas = gasPrice
                tx.nonce = nonce
                tx.priorityFeeGwei = priorityFee
            } else if tx.coin.chain.name  == Chain.Avalache.name  {
                print("The loadData for \(tx.coin.ticker)")
                let (gasPrice,priorityFee,nonce) = try await avax.getGasInfo(fromAddress: tx.fromAddress)
                tx.gas = gasPrice
                tx.nonce = nonce
                tx.priorityFeeGwei = priorityFee
            }
            else if tx.coin.chain.name  == Chain.THORChain.name  {
                // THORChain gas fee is 0.02 RUNE fixed
                tx.gas = "0.02"
            } else if tx.coin.chain.name == Chain.GaiaChain.name {
                tx.gas = "0.0075"
            }
            
        } catch {
            if let err =  error as? HelperError {
                switch err{
                case HelperError.runtimeError(let desc):
                    print(desc)
                }
            }
            print("error fetching data: \(error.localizedDescription)")
        }
    }
    
    private func getTransactionPlan(tx: SendTransaction, key:String) -> TW_Bitcoin_Proto_TransactionPlan? {
        let totalAmountNeeded = tx.amountInSats + tx.feeInSats
        
        guard let utxoInfo = utxo.blockchairData[key]?.selectUTXOsForPayment(amountNeeded: Int64(totalAmountNeeded)).map({
            UtxoInfo(
                hash: $0.transactionHash ?? "",
                amount: Int64($0.value ?? 0),
                index: UInt32($0.index ?? -1)
            )
        }), !utxoInfo.isEmpty else {
            return nil
        }
        
        let keysignPayload = KeysignPayload(
            coin: tx.coin,
            toAddress: tx.toAddress,
            toAmount: tx.amountInSats,
            chainSpecific: BlockChainSpecific.UTXO(byteFee: tx.feeInSats),
            utxos: utxoInfo,
            memo: tx.memo,
            swapPayload: nil
        )
        
        if let vault = ApplicationState.shared.currentVault {
            if let helper = UTXOChainsHelper.getHelper(vault: vault, coin: tx.coin) {
                let transactionPlanResult = helper.getBitcoinTransactionPlan(keysignPayload: keysignPayload)
                switch transactionPlanResult {
                case .success(let plan):
                    return plan
                case .failure(let error):
                    print("Error generating transaction plan: \(error.localizedDescription)")
                    return nil
                }
            }
        }
        return nil
    }
    
    
    func setMaxValues(tx: SendTransaction)  {
        let coinName = tx.coin.chain.name.lowercased()
        let key: String = "\(tx.fromAddress)-\(coinName)"
        isLoading = true
        
        if  tx.coin.chain.chainType == ChainType.UTXO {
            
            tx.amount = utxo.blockchairData[key]?.address?.balanceInBTC ?? "0.0"
            
            if let plan = getTransactionPlan(tx: tx, key: key) {
                tx.amount = utxo.blockchairData[key]?.address?.formatAsBitcoin(Int(plan.amount)) ?? "0.0"
            }
            Task{
                await convertToUSD(newValue: tx.amount, tx: tx)
                isLoading = false
            }
        } else if tx.coin.chain.name.lowercased() == Chain.Ethereum.name.lowercased() {
            Task {
                do {
                    let (gasPrice, _, _) = try await EtherScanService.shared.getETHGasInfo(fromAddress: tx.fromAddress)
                    
                    guard let gasLimitBigInt = BigInt(tx.coin.feeDefault) else {
                        print("Invalid gas limit")
                        return
                    }
                    
                    guard let gasPriceBigInt = BigInt(gasPrice) else {
                        print("Invalid gas price")
                        return
                    }
                    
                    let gasPriceGwei: BigInt = gasPriceBigInt
                    let gasPriceWei: BigInt = gasPriceGwei * BigInt(EVMHelper.weiPerGWei)
                    let totalFeeWei: BigInt = gasLimitBigInt * gasPriceWei
                    
                    tx.amount = "\(tx.coin.getMaxValue(totalFeeWei))"
                } catch {
                    tx.amount = tx.coin.balanceString
                    print("Failed to get EVM balance, error: \(error.localizedDescription)")
                }
                
                await convertToUSD(newValue: tx.amount, tx: tx)
                isLoading = false
            }
        } else if tx.coin.chain.name.lowercased() == Chain.Avalache.name.lowercased() {
            Task {
                do {
                    let (gasPrice, _, _) = try await AvalancheService.shared.getGasInfo(fromAddress: tx.fromAddress)
                    
                    guard let gasLimitBigInt = BigInt(tx.coin.feeDefault) else {
                        print("Invalid gas limit")
                        return
                    }
                    
                    guard let gasPriceBigInt = BigInt(gasPrice) else {
                        print("Invalid gas price")
                        return
                    }
                    
                    let gasPriceGwei: BigInt = gasPriceBigInt
                    let gasPriceWei: BigInt = gasPriceGwei * BigInt(EVMHelper.weiPerGWei)
                    let totalFeeWei: BigInt = gasLimitBigInt * gasPriceWei
                    
                    tx.amount = "\(tx.coin.getMaxValue(totalFeeWei))"
                } catch {
                    tx.amount = tx.coin.balanceString
                    print("Failed to get EVM balance, error: \(error.localizedDescription)")
                }
                
                await convertToUSD(newValue: tx.amount, tx: tx)
                isLoading = false
            }
        }  else if tx.coin.chain.name.lowercased() == Chain.THORChain.name.lowercased() {
            Task{
                do{
                    let thorBalances = try await self.thor.fetchBalances(tx.fromAddress)
                    if let priceRateUsd = CryptoPriceService.shared.cryptoPrices?.prices[Chain.THORChain.name.lowercased()]?["usd"] {
                        tx.coin.priceRate = priceRateUsd
                    }
                    
                    tx.coin.rawBalance = thorBalances.runeBalance() ?? "0"
                    tx.amount = "\(tx.coin.getMaxValue(BigInt(THORChainHelper.THORChainGas)))"
                    await convertToUSD(newValue: tx.amount, tx: tx)
                }catch{
                    print("fail to get THORChain balance,error:\(error.localizedDescription)")
                }
                isLoading = false
            }
        } else if tx.coin.chain.name.lowercased() == Chain.Solana.name.lowercased() {
            Task{
                await sol.getSolanaBalance(tx:tx)
                await sol.fetchRecentBlockhash()
                guard
                    let feeLamportsStr = sol.feeInLamports,
                    let feeInLamports = BigInt(feeLamportsStr) else {
                    print("Invalid fee In Lamports")
                    return
                }
                
                tx.coin.rawBalance = sol.rawBalance
                tx.amount = "\(tx.coin.getMaxValue(feeInLamports))"
                await convertToUSD(newValue: tx.amount, tx: tx)
                isLoading = false
            }
        }
    }
    
    func convertUSDToCoin(newValue: String, tx: SendTransaction) async {
        
        await cryptoPrice.fetchCryptoPrices()
        
        if let priceRateUsd = cryptoPrice.cryptoPrices?.prices[tx.coin.priceProviderId]?["usd"] {
            if let newValueDouble = Double(newValue) {
                let newValueCoin = newValueDouble / priceRateUsd
                tx.amount = String(newValueCoin)
            } else {
                tx.amount = ""
            }
        }
    }
    
    func convertToUSD(newValue: String, tx: SendTransaction) async {
        
        await cryptoPrice.fetchCryptoPrices()
        
        if let priceRateUsd = cryptoPrice.cryptoPrices?.prices[tx.coin.priceProviderId]?["usd"] {
            if let newValueDouble = Double(newValue) {
                let newValueUSD = String(format: "%.2f", newValueDouble * priceRateUsd)
                tx.amountInUSD = newValueUSD.isEmpty ? "" : newValueUSD
            } else {
                tx.amountInUSD = ""
            }
        }
    }
    
    func validateAddress(tx: SendTransaction, address: String) {
        guard let coinType = tx.coin.getCoinType() else {
            print("Coin type not found on Wallet Core")
            return
        }
        
        isValidAddress = coinType.validate(address: address)
    }
    
    func validateForm(tx: SendTransaction) -> Bool {
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
        
        let coinName = tx.coin.chain.name.lowercased()
        let key: String = "\(tx.fromAddress)-\(coinName)"
        
        if  tx.coin.chain.chainType == ChainType.UTXO {
            let walletBalanceInSats = utxo.blockchairData[key]?.address?.balance ?? 0
            let totalTransactionCostInSats = tx.amountInSats + tx.feeInSats
            print("Total transaction cost: \(totalTransactionCostInSats)")
            
            if totalTransactionCostInSats > walletBalanceInSats {
                errorMessage = "walletBalanceExceededError"
                showAlert = true
                logger.log("Total transaction cost exceeds wallet balance.")
                isValidForm = false
            }
        } else if tx.coin.chain.name.lowercased() == Chain.Solana.name.lowercased() {
            
            guard let walletBalanceInLamports = sol.balance else {
                errorMessage = "unavailableBalanceError"
                showAlert = true
                logger.log("Wallet balance is not available for Solana.")
                isValidForm = false
                return isValidForm
            }
            
            let optionalGas: String? = tx.gas
            guard let feeStr = optionalGas, let feeInLamports = Decimal(string: feeStr) else {
                errorMessage = "invalidGasFeeError"
                showAlert = true
                logger.log("Invalid gas fee for Solana.")
                isValidForm = false
                return isValidForm
            }
            
            guard let amountInSOL = Decimal(string: tx.amount) else {
                errorMessage = "invalidTransactionAmountError"
                showAlert = true
                logger.log("Invalid transaction amount for Solana.")
                isValidForm = false
                return isValidForm
            }
            
            let amountInLamports = amountInSOL * Decimal(1_000_000_000)
            
            let totalCostInLamports = amountInLamports + feeInLamports
            if totalCostInLamports > Decimal(walletBalanceInLamports) {
                errorMessage = "walletBalanceExceededSolanaError"
                showAlert = true
                logger.log("Total transaction cost exceeds wallet balance for Solana.")
                isValidForm = false
            }
        }
        
        return isValidForm
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
}
