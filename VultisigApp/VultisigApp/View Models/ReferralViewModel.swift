//
//  ReferralViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-13.
//

import SwiftUI

@MainActor
class ReferralViewModel: ObservableObject {
    @Published var isLoading: Bool = false
    
    // Generated Referral Code
    @AppStorage("savedGeneratedReferralCode") var savedGeneratedReferralCode: String = ""
    @Published var referralCode: String = ""
    @Published var showReferralAvailabilityError: Bool = false
    @Published var referralAvailabilityErrorMessage: String = ""
    @Published var showReferralAvailabilitySuccess: Bool = false
    @Published var isReferralCodeVerified: Bool = false
    @Published var expireInCount: Int = 0
    
    @Published var showReferralAlert = false
    @Published var referralAlertMessage = ""
    
    // Fees
    @Published var nativeCoin: Coin? = nil
    @Published var registrationFee: Decimal = 0
    @Published var feePerBlock: Decimal = 0
    @Published var isFeesLoading: Bool = false
    
    let blockchainService = BlockChainService.shared
    
    var registrationFeeFiat: String {
        getFiatAmount(for: getRegistrationFee())
    }
    
    var totalFee: Decimal {
        getTotalFee()
    }
    
    var totalFeeFiat: String {
        getFiatAmount(for: getTotalFee())
    }
    
    var isTotalFeesLoading: Bool {
        guard expireInCount>0 else {
            return true
        }
        
        return isFeesLoading
    }
    
    func verifyReferralCode() async {
        isLoading = true
        resetReferralData()
        nameErrorCheck(code: referralCode, forReferralCode: true)
        
        guard !showReferralAvailabilityError else {
            return
        }
        
        await checkNameAvailability(code: referralCode)
    }
    
    func handleCounterIncrease() {
        expireInCount += 1
    }
    
    func handleCounterDecrease() {
        guard expireInCount > 0 else {
            return
        }
        
        expireInCount -= 1
    }
    
    func verifyReferralEntries(tx: SendTransaction, functionCallViewModel: FunctionCallViewModel) async {
        await verifyReferralCode()
        
        guard isReferralCodeVerified else {
            showAlert(with: "pickValidCode")
            return
        }
        
        guard expireInCount>0 else {
            showAlert(with: "pickValidExpiration")
            return
        }
        
        guard enoughGas(tx: tx) else {
            showAlert(with: "insufficientBalance")
            return
        }
        
        createTransaction(tx: tx, functionCallViewModel: functionCallViewModel)
    }
    
    func getRegistrationFee() -> Decimal {
        registrationFee / 100_000_000
    }
    
    func getTotalFee() -> Decimal {
        let amount = registrationFee + (feePerBlock * Decimal(expireInCount) * 5256000)
        return amount / 100_000_000
    }
    
    func getFiatAmount(for amount: Decimal) -> String {
        guard let nativeCoin else {
            return ""
        }
        
        let fiatAmount = RateProvider.shared.fiatBalance(value: amount, coin: nativeCoin)
        return fiatAmount.formatToFiat(includeCurrencySymbol: true, useAbbreviation: true)
    }
    
    func getNativeCoin(tx: SendTransaction) {
        nativeCoin = ApplicationState.shared.currentVault?.coins.first(where: { $0.chain == .thorChain && $0.isNativeToken })
        
        if let nativeCoin {
            tx.coin = nativeCoin
        }
    }
    
    func loadGasInfoForSending(tx: SendTransaction) async{
        do {
            let chainSpecific = try await blockchainService.fetchSpecific(tx: tx)
            tx.gas = chainSpecific.gas
        } catch {
            print("error fetching data: \(error.localizedDescription)")
        }
    }
    
    func createTransaction(tx: SendTransaction, functionCallViewModel: FunctionCallViewModel) {
        setupTransaction(tx: tx)
        functionCallViewModel.currentIndex = 2
    }
    
    func resetAllData() {
        referralCode = ""
        showReferralAvailabilityError = false
        referralAvailabilityErrorMessage = ""
        showReferralAvailabilitySuccess = false
        isReferralCodeVerified = false
        expireInCount = 0
        
        showReferralAlert = false
        referralAlertMessage = ""
        
        
        nativeCoin = nil
        registrationFee = 0
        feePerBlock = 0
        isFeesLoading = false
    }
    
    private func setupTransaction(tx: SendTransaction) {
        tx.amount = totalFee.formatDecimalToLocale()
        
        let fnCallInstance = FunctionCallInstance.custom(FunctionCallCustom())
        tx.memoFunctionDictionary = fnCallInstance.toDictionary()
        tx.transactionType = fnCallInstance.getTransactionType()
        
        guard let nativeCoin else {
            return
        }
        
        let memo = "~:\(referralCode.uppercased()):THOR:\(nativeCoin.address):\(nativeCoin.address)"
        tx.memo = memo
        tx.coin = nativeCoin
        tx.fromAddress = nativeCoin.address
    }
    
    private func showAlert(with message: String) {
        referralAlertMessage = message
        showReferralAlert = true
    }
    
    private func showNameError(with message: String) {
        if message == "alreadyTaken" {
            referralAvailabilityErrorMessage = message
        } else {
            referralAvailabilityErrorMessage = "invalid"
        }
        
        showReferralAvailabilityError = true
        isLoading = false
    }
    
    private func saveReferralCode() {
        isReferralCodeVerified = true
        showReferralAvailabilitySuccess = true
        isLoading = false
        isReferralCodeVerified = true
    }
    
    func resetReferralData() {
        showReferralAvailabilityError = false
        referralAvailabilityErrorMessage = ""
        showReferralAvailabilitySuccess = false
        isReferralCodeVerified = false
    }
    
    private func nameErrorCheck(code: String, forReferralCode: Bool) {
        guard !code.isEmpty else {
            showNameError(with: "emptyField")
            return
        }
        
        guard !containsWhitespace(code) else {
            showNameError(with: "whitespaceNotAllowed")
            return
        }
        
        if !forReferralCode {
            guard code != savedGeneratedReferralCode else {
                showNameError(with: "referralCodeMatch")
                return
            }
        }
        
        guard code.count <= 4 else {
            showNameError(with: "referralLaunchCodeLengthError")
            return
        }
    }
    
    private func checkNameAvailability(code: String) async {
        let urlString = Endpoint.getUserDetails(for: code)
        guard let url = URL(string: urlString) else {
            showNameError(with: "systemErrorMessage")
            return
        }
        
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    showNameError(with: "alreadyTaken")
                } else {
                    saveReferralCode()
                }
            }
        } catch {
            showNameError(with: "systemErrorMessage")
        }
        isLoading = false
    }
    
    func calculateFees() async {
        isFeesLoading = true
        
        guard let url = URL(string: Endpoint.ReferralFees) else {
            print("Invalid URL")
            isFeesLoading = false
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoder = JSONDecoder()
            let info = try decoder.decode(ThorchainNetworkAllFees.self, from: data)
            registrationFee = Decimal(string: info.tns_register_fee_rune) ?? 0
            feePerBlock = Decimal(string: info.tns_fee_per_block_rune) ?? 0
            isFeesLoading = false
        } catch {
            print("Network or decoding error: \(error)")
            isFeesLoading = false
        }
    }
    
    private func containsWhitespace(_ text: String) -> Bool {
        return text.rangeOfCharacter(from: .whitespacesAndNewlines) != nil
    }
    
    private func enoughGas(tx: SendTransaction) -> Bool {
        let decimals = tx.coin.decimals
        let gas = Decimal(tx.gas) / pow(10,decimals)
        let amount = totalFee + gas
        let vaultAmount = nativeCoin?.balanceDecimal ?? 0
        
        if vaultAmount >= amount {
            return true
        } else {
            return false
        }
    }
}
