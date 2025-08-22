//
//  ReferralViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-13.
//

import BigInt
import SwiftUI
import SwiftData

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
    @Published var expireInCount: Int = 1
    
    @Published var showReferralAlert = false
    @Published var referralAlertMessage = ""
    
    // Fees
    @Published var nativeCoin: Coin? = nil
    @Published var registrationFee: Decimal = 0
    @Published var feePerBlock: Decimal = 0
    @Published var isFeesLoading: Bool = false
    
    // Expires On
    @Published var expiresOn: String = ""
    
    // Collected Rewards
    @Published var collectedRewards: String = ""
    
    let blockchainService = BlockChainService.shared
    private let thorchainReferralService = THORChainAPIService()
    
    private(set) var thornameDetails: THORName?
    private(set) var thornameVault: Vault?
    private(set) var currentBlockheight: UInt64 = 0

    var yourVaultName: String? {
        thornameVault?.name
    }
    
    var hasReferralCode: Bool {
        savedGeneratedReferralCode.isNotEmpty
    }
    
    var canEditCode: Bool {
        !isLoading && thornameDetails != nil && thornameVault != nil
    }
    
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
        let amount: Decimal
        if expireInCount > 1 {
            amount = (feePerBlock * Decimal(ReferralExpiryDataCalculator.blockPerYear * UInt64(expireInCount - 1)))
        } else {
            // Registration comes with 1 free year, but sending exactly 10 RUNE fails
            // So we need to send a little bit more
            amount = feePerBlock
        }
        
        return (registrationFee + amount) / 100_000_000
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
        expireInCount = 1
        
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
        defer { isLoading = false }
        do {
            _ = try await thorchainReferralService.getThornameLookup(name: code)
            showNameError(with: "alreadyTaken")
        } catch {
            guard error as? THORChainAPIError == .thornameNotFound else {
                showNameError(with: "systemErrorMessage")
                return
            }
            
            saveReferralCode()
        }
    }
    
    func calculateFees() async {
        isFeesLoading = true
        
        do {
            let info = try await thorchainReferralService.getNetworkInfo()
            registrationFee = info.tns_register_fee_rune.toDecimal()
            feePerBlock = info.tns_fee_per_block_rune.toDecimal()
            isFeesLoading = false
        } catch {
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
        
        return vaultAmount >= amount
    }
    
    func fetchReferralCodeDetails(vaults: [Vault]) async {
        await MainActor.run { isLoading = true }
        do {
            let details = try await thorchainReferralService.getThornameDetails(name: savedGeneratedReferralCode)
            let lastBlock = try await thorchainReferralService.getLastBlock()
            let expiresOn = ReferralExpiryDataCalculator.getFormattedExpiryDate(expiryBlock: details.expireBlockHeight, currentBlock: lastBlock)
            let collectedRunes = await calculateCollectedRewards(details: details)
            // Saved referral code and vault association
            let thornameVault = vaults.first { $0.nativeCoin(for: .thorChain)?.address == details.owner }
            
            await MainActor.run {
                self.currentBlockheight = lastBlock
                self.expiresOn = expiresOn
                self.collectedRewards = collectedRunes
                self.thornameDetails = details
                self.thornameVault = thornameVault
            }
        } catch {
            await MainActor.run {
                self.expiresOn = "-"
                self.collectedRewards = "-"
            }
        }
        
        await MainActor.run { isLoading = false }
    }
    
    func calculateCollectedRewards(details: THORName) async -> String {
        let assetDecimals: Int
        let assetMultiplier: Decimal
        let assetTicker: String
        
        if details.isDefaultPreferredAsset {
            let runeCoin = TokensStore.TokenSelectionAssets.first(where: { $0.chain == .thorChain && $0.isNativeToken })
            guard let runeCoin else { return "" }
            assetDecimals = runeCoin.decimals
            assetMultiplier = 1
            assetTicker = runeCoin.ticker
        } else {
            let preferredAsset = try? await thorchainReferralService.getPoolAsset(asset: details.preferredAsset)
            guard let preferredAsset else { return "" }
            assetDecimals = preferredAsset.decimals ?? 6
            assetMultiplier = (preferredAsset.assetTorPrice.toDecimal() / 100_000_000)
            assetTicker = String(preferredAsset.asset.split(separator: ".")[1].split(separator: "-").first ?? "")
        }

        let collectedRunesAmount = details.affiliateCollectorRune.toDecimal()
        let collectedAssetAmount = collectedRunesAmount * assetMultiplier / pow(10, assetDecimals)
        
        return "\(collectedAssetAmount.formatForDisplay()) \(assetTicker)"
    }
    
    func setup(tx: SendTransaction) {
        let newValueFiat = tx.amountDecimal * Decimal(tx.coin.price)
        let truncatedValueFiat = newValueFiat.truncated(toPlaces: 2) // Assuming 2 decimal places for fiat
        tx.amountInFiat = truncatedValueFiat.formatToDecimal(digits: tx.coin.decimals)
    }
}
