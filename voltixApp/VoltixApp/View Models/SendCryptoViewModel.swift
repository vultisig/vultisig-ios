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
    @Published var cryptoPrice = CryptoPriceService.shared
    @Published var utxo = BlockchairService.shared
    let maya = MayachainService.shared
    let atom = GaiaService.shared
    let kujira = KujiraService.shared
    
    private let mediator = Mediator.shared
    
    let totalViews = 5
    let titles = ["send", "verify", "pair", "keysign", "done"]
    
    let logger = Logger(subsystem: "send-input-details", category: "transaction")
    
    func loadGasInfoForSending(tx: SendTransaction) async{
        do {
            switch tx.coin.chain {
            case .bitcoin,.bitcoinCash,.dogecoin,.dash,.litecoin:
                let sats = try await utxo.fetchSatsPrice(coin: tx.coin)
                tx.gas = String(sats)
            case .ethereum, .avalanche, .bscChain, .arbitrum, .base, .optimism, .polygon:
                let service = try EvmServiceFactory.getService(forChain: tx.coin)
                let (gasPrice,priorityFee,nonce) = try await service.getGasInfo(fromAddress: tx.fromAddress)
                
                tx.gas = gasPrice
                tx.nonce = Int64(nonce)
                tx.priorityFeeWei = Int64(priorityFee)
            case .thorChain,.mayaChain, .kujira:
                tx.gas = "0.02"
            case .gaiaChain:
                tx.gas = "0.0075"
            case .solana:
                let (_,feeInLamports) = try await sol.fetchRecentBlockhash()
                tx.gas = String(feeInLamports)
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
        
        guard let utxoInfo = utxo.blockchairData.get(key)?.selectUTXOsForPayment(amountNeeded: Int64(tx.amountInSats)).map({
            UtxoInfo(
                hash: $0.transactionHash ?? "",
                amount: Int64($0.value ?? 0),
                index: UInt32($0.index ?? -1)
            )
        }), !utxoInfo.isEmpty else {
            return nil
        }
        
        let totalSelectedAmount = utxoInfo.reduce(0) { $0 + $1.amount }
        
        let keysignPayload = KeysignPayload(
            coin: tx.coin,
            toAddress: tx.toAddress,
            toAmount: BigInt(totalSelectedAmount),
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
        switch tx.coin.chain {
        case .bitcoin,.dogecoin,.litecoin,.bitcoinCash,.dash:
            tx.amount = utxo.blockchairData.get(key)?.address?.balanceInBTC ?? "0.0"
            if let plan = getTransactionPlan(tx: tx, key: key), plan.amount > 0 {
                tx.amount = utxo.blockchairData.get(key)?.address?.formatAsBitcoin(Int(plan.amount)) ?? "0.0"
            }
            Task{
                await convertToFiat(newValue: tx.amount, tx: tx)
                isLoading = false
            }
        case .ethereum, .avalanche, .bscChain, .arbitrum, .base, .optimism, .polygon:
            Task {
                do {
                    let service = try EvmServiceFactory.getService(forChain: tx.coin)
                    let (gasPrice,_,_) = try await service.getGasInfo(fromAddress: tx.fromAddress)
                    
                    guard let gasLimitBigInt = BigInt(tx.coin.feeDefault) else {
                        print("Invalid gas limit")
                        return
                    }
                    
                    guard let gasPriceWei = BigInt(gasPrice) else {
                        print("Invalid gas price")
                        return
                    }
                    
                    let totalFeeWei: BigInt = gasLimitBigInt * gasPriceWei
                    
                    tx.amount = "\(tx.coin.getMaxValue(totalFeeWei))"
                } catch {
                    tx.amount = tx.coin.balanceString
                    print("Failed to get EVM balance, error: \(error.localizedDescription)")
                }
                
                await convertToFiat(newValue: tx.amount, tx: tx)
                isLoading = false
            }
            
        case .solana:
            Task{
                do{
                    let (rawBalance,priceRate) = try await sol.getSolanaBalance(coin: tx.coin)
                    let (_,feeLamportsStr) = try await sol.fetchRecentBlockhash()
                    guard
                        let feeInLamports = BigInt(feeLamportsStr) else {
                        print("Invalid fee In Lamports")
                        return
                    }
                    tx.coin.rawBalance = rawBalance
                    tx.coin.priceRate = priceRate
                    tx.amount = "\(tx.coin.getMaxValue(feeInLamports))"
                    await convertToFiat(newValue: tx.amount, tx: tx)
                } catch {
                    print("fail to load solana balances,error:\(error.localizedDescription)")
                }
                
                isLoading = false
            }
            
        case .kujira, .gaiaChain, .mayaChain, .thorChain:
            Task {
                do{
                    let (_, _, _) = try await BalanceService.shared.balance(for: tx.coin)
                    tx.amount = "\(tx.coin.getMaxValue(BigInt(tx.gasDecimal)))"
                    await convertToFiat(newValue: tx.amount, tx: tx)
                } catch {
                    print("fail to get Maya balance,error:\(error.localizedDescription)")
                }
                isLoading = false
            }
        }
        
    }
    
    func convertFiatToCoin(newValue: String, tx: SendTransaction) async {
        
        let priceRateFiat = await CryptoPriceService.shared.getPrice(priceProviderId: tx.coin.priceProviderId)
        if let newValueDouble = Double(newValue) {
            let newValueCoin = newValueDouble / priceRateFiat
            tx.amount = String(format: "%.9f", newValueCoin)
        } else {
            tx.amount = ""
        }
        
    }
    
    func convertToFiat(newValue: String, tx: SendTransaction) async {
        
        let priceRateFiat = await CryptoPriceService.shared.getPrice(priceProviderId: tx.coin.priceProviderId)
        if let newValueDouble = Double(newValue) {
            let newValueFiat = String(format: "%.2f", newValueDouble * priceRateFiat)
            tx.amountInFiat = newValueFiat.isEmpty ? "" : newValueFiat
        } else {
            tx.amountInFiat = ""
        }
        
    }
    
    func validateAddress(tx: SendTransaction, address: String) {
        guard let coinType = tx.coin.getCoinType() else {
            print("Coin type not found on Wallet Core")
            return
        }
        if tx.coin.chain == .mayaChain {
            isValidAddress = AnyAddress.isValidBech32(string: address, coin: .thorchain, hrp: "maya")
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
            let walletBalanceInSats = utxo.blockchairData.get(key)?.address?.balance ?? 0
            let totalTransactionCostInSats = tx.amountInSats + BigInt(tx.feeInSats)
            print("Total transaction cost: \(totalTransactionCostInSats)")
            
            if totalTransactionCostInSats > walletBalanceInSats {
                errorMessage = "walletBalanceExceededError"
                showAlert = true
                logger.log("Total transaction cost exceeds wallet balance.")
                isValidForm = false
            }
        } else if tx.coin.chain == .solana {
            let walletBalanceInLamports = tx.coin.rawBalance
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
            if totalCostInLamports > (Decimal(string: walletBalanceInLamports) ?? 0) {
                errorMessage = "walletBalanceExceededSolanaError"
                showAlert = true
                logger.log("Total transaction cost exceeds wallet balance for Solana.")
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
}
