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
    enum ReferralCodeAvailabilityStatus {
        case available
        case alreadyTaken
        
        var color: Color {
            switch self {
            case .available:
                return Theme.colors.alertSuccess
            case .alreadyTaken:
                return Theme.colors.alertError
            }
        }
        
        var description: String {
            switch self {
            case .available:
                return "available".localized
            case .alreadyTaken:
                return "alreadyTaken".localized
            }
        }
    }
    
    @Published var isLoading: Bool = false
    
    @Published var referralCode: String = ""
    @Published var referralAvailabilityErrorMessage: String?
    @Published var availabilityStatus: ReferralCodeAvailabilityStatus?
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
    
    var thornameDetails: THORName?
    var currentBlockheight: UInt64 = 0
    
    @Published var currentVault: Vault?
    
    init(
        thornameDetails: THORName? = nil,
        currentBlockheight: UInt64 = 0
    ) {
        self.thornameDetails = thornameDetails
        self.currentBlockheight = currentBlockheight
    }
    
    var createReferralButtonEnabled: Bool {
        availabilityStatus == .available && !isLoading
    }
    
    var yourVaultName: String? {
        currentVault?.name
    }
    
    var savedReferralCode: String {
        currentVault?.referralCode?.code ?? .empty
    }
    
    var hasReferralCode: Bool {
        savedReferralCode.isNotEmpty
    }
    
    var canEditCode: Bool {
        !isLoading && thornameDetails != nil
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
        
        guard referralAvailabilityErrorMessage == nil else {
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
    
    func verifyReferralEntries(tx: SendTransaction) async -> Bool {
        await verifyReferralCode()
        
        guard isReferralCodeVerified else {
            showAlert(with: "pickValidCode")
            return false
        }
        
        guard enoughGas(tx: tx) else {
            showAlert(with: "insufficientBalance")
            return false
        }
        
        setupTransaction(tx: tx)
        return true
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
        nativeCoin = tx.vault?.coins.first(where: { $0.chain == .thorChain && $0.isNativeToken })
        
        if let nativeCoin {
            tx.coin = nativeCoin
        }
    }
    
    func loadGasInfoForSending(tx: SendTransaction) async {
        do {
            let chainSpecific = try await blockchainService.fetchSpecific(tx: tx)
            tx.gas = chainSpecific.gas
        } catch {
            print("error fetching data: \(error.localizedDescription)")
        }
    }
    
    func resetAllData() {
        referralCode = ""
        referralAvailabilityErrorMessage = nil
        availabilityStatus = nil
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
        
        guard let currentVault else {
            return
        }
        
        let fnCallInstance = FunctionCallInstance.custom(FunctionCallCustom(tx: tx, vault: currentVault))
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
            availabilityStatus = .alreadyTaken
        } else {
            referralAvailabilityErrorMessage = message.localized
        }
            
        isLoading = false
    }
    
    private func saveReferralCode() {
        isReferralCodeVerified = true
        availabilityStatus = .available
        isLoading = false
        isReferralCodeVerified = true
    }
    
    func resetReferralData() {
        referralAvailabilityErrorMessage = nil
        availabilityStatus = nil
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
            guard code != savedReferralCode else {
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
            let info = try await thorchainReferralService.getNetwork()
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
    
    func fetchReferralCodeDetails() async {
        await MainActor.run { isLoading = true }
        guard savedReferralCode.isNotEmpty else {
            await MainActor.run { isLoading = false }
            return
        }
        do {
            let details = try await thorchainReferralService.getThornameDetails(name: savedReferralCode)
            let lastBlock = try await thorchainReferralService.getLastBlock()
            let expiresOn = ReferralExpiryDataCalculator.getFormattedExpiryDate(expiryBlock: details.expireBlockHeight, currentBlock: lastBlock)
            let collectedRunes = await calculateCollectedRewards(details: details)
            // Saved referral code and vault association
            await MainActor.run {
                self.currentBlockheight = lastBlock
                self.expiresOn = expiresOn
                self.collectedRewards = collectedRunes
                self.thornameDetails = details
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
    
    func setup(tx: SendTransaction, defaultVault: Vault?) {
        self.currentVault = currentVault ?? defaultVault
        let newValueFiat = tx.amountDecimal * Decimal(tx.coin.price)
        let truncatedValueFiat = newValueFiat.truncated(toPlaces: 2) // Assuming 2 decimal places for fiat
        tx.amountInFiat = truncatedValueFiat.formatToDecimal(digits: tx.coin.decimals)
        tx.vault = currentVault
        getNativeCoin(tx: tx)
    }
    
    func updateReferralCode(code: String) {
        guard let currentVault else {
            showNameError(with: "systemErrorMessage")
            return
        }        
        if let vaultReferral = currentVault.referralCode {
            vaultReferral.code = code
        } else {
            let referral = ReferralCode(code: code, vault: currentVault)
            Storage.shared.insert(referral)
        }
        
        do {
            try Storage.shared.save()
        } catch {
            showNameError(with: "systemErrorMessage")
        }
    }
    
    func fetchVaultData() async {
        await MainActor.run { isLoading = true }
        guard
            let currentVault,
            currentVault.referralCode == nil,
            let thorAddress = currentVault.nativeCoin(for: .thorChain)?.address
        else {
            await MainActor.run { isLoading = false }
            return
        }
        
        // Fetch thorname by reverse lookup if it hasn't been set yet
        let thorname = try? await thorchainReferralService.getAddressLookup(address: thorAddress)
        // If thorname exist, we'll save it dynamically
        if let thorname {
            let normalisedThorname = thorname.uppercased()
            let referralCode = ReferralCode(code: normalisedThorname, vault: currentVault)
            Storage.shared.insert(referralCode)
            try? Storage.shared.save()
        }
        await MainActor.run { isLoading = false }
    }
}
