//
//  ReferralDetailsViewModel.swift
//  VultisigApp
//
//  Form-state-on-VM rewrite of the Referral create flow. Owns every form
//  field directly (replacing the legacy `FunctionCallForm`'s `@Published`
//  fields threaded via `tx:` parameters) and produces an immutable
//  `SendTransaction` only on Continue via `buildSendTransaction()`.
//
//  Replaces `ReferralViewModel`. Network calls go through closure-injected
//  endpoints so unit tests can drive happy/error paths without hitting the
//  real THORChain API.
//

import BigInt
import Foundation
import OSLog
import SwiftUI
import SwiftData
import VultisigCommonData

@MainActor
@Observable
final class ReferralDetailsViewModel {

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

    @ObservationIgnored private let logger = Logger(subsystem: "com.vultisig.app", category: "referral-details-vm")
    @ObservationIgnored private let interactor: SendInteractor
    @ObservationIgnored private let thorchainService: THORChainAPIService
    @ObservationIgnored private let saveReferralCode: @MainActor (ReferralCode) -> Void

    // MARK: - Identity (immutable once set)
    let vault: Vault

    // MARK: - Network-sourced state
    var thornameDetails: THORName?
    var currentBlockheight: UInt64
    var expiresOn: String = ""
    var collectedRewards: String = ""

    // MARK: - Form fields
    var referralCode: String = ""
    var expireInCount: Int = 1

    // MARK: - Validation state
    var availabilityStatus: ReferralCodeAvailabilityStatus?
    var referralAvailabilityErrorMessage: String?
    var isReferralCodeVerified: Bool = false

    // MARK: - Fee state
    var nativeCoin: Coin?
    var registrationFee: Decimal = 0
    var feePerBlock: Decimal = 0
    var isFeesLoading: Bool = false

    // MARK: - Async state
    var isLoading: Bool = false

    // MARK: - Send-transaction props (replaces tx.gas)
    var gas: BigInt = .zero

    // MARK: - Alert
    var showReferralAlert: Bool = false
    var referralAlertMessage: String = ""

    // MARK: - Init

    init(
        vault: Vault,
        thornameDetails: THORName? = nil,
        currentBlockheight: UInt64 = 0,
        interactor: SendInteractor = DefaultSendInteractor.live,
        thorchainService: THORChainAPIService = THORChainAPIService(),
        saveReferralCode: @escaping @MainActor (ReferralCode) -> Void = ReferralDetailsViewModel.defaultSaveReferralCode
    ) {
        self.vault = vault
        self.thornameDetails = thornameDetails
        self.currentBlockheight = currentBlockheight
        self.interactor = interactor
        self.thorchainService = thorchainService
        self.saveReferralCode = saveReferralCode
        self.nativeCoin = vault.coins.first(where: { $0.chain == .thorChain && $0.isNativeToken })
    }

    // MARK: - Derived state

    var createReferralButtonEnabled: Bool {
        availabilityStatus == .available && !isLoading
    }

    var yourVaultName: String? {
        vault.name
    }

    var savedReferralCode: String {
        vault.referralCode?.code ?? .empty
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
        getFiatAmount(for: totalFee)
    }

    var isTotalFeesLoading: Bool {
        guard expireInCount > 0 else { return true }
        return isFeesLoading
    }

    // MARK: - Pure helpers (no side effects)

    func getRegistrationFee() -> Decimal {
        registrationFee / 100_000_000
    }

    func getTotalFee() -> Decimal {
        let amount: Decimal
        if expireInCount > 1 {
            amount = feePerBlock * Decimal(ReferralExpiryDataCalculator.blockPerYear * UInt64(expireInCount - 1))
        } else {
            // Registration comes with 1 free year, but sending exactly 10 RUNE fails
            // so we need to send a little bit more.
            amount = feePerBlock
        }
        return (registrationFee + amount) / 100_000_000
    }

    func getFiatAmount(for amount: Decimal) -> String {
        guard let nativeCoin else { return "" }
        let fiatAmount = RateProvider.shared.fiatBalance(value: amount, coin: nativeCoin)
        return fiatAmount.formatToFiat(includeCurrencySymbol: true)
    }

    // MARK: - Counter handlers

    func handleCounterIncrease() {
        expireInCount += 1
    }

    func handleCounterDecrease() {
        // Counter must stay ≥ 1 — 0 makes `isTotalFeesLoading` flip true while
        // `getTotalFee()` still prices it like the 1-year case.
        guard expireInCount > 1 else { return }
        expireInCount -= 1
    }

    // MARK: - Reset

    func resetAllData() {
        referralCode = ""
        referralAvailabilityErrorMessage = nil
        availabilityStatus = nil
        isReferralCodeVerified = false
        expireInCount = 1
        showReferralAlert = false
        referralAlertMessage = ""
        registrationFee = 0
        feePerBlock = 0
        isFeesLoading = false
    }

    func resetReferralData() {
        referralAvailabilityErrorMessage = nil
        availabilityStatus = nil
        isReferralCodeVerified = false
    }

    // MARK: - Code availability

    func verifyReferralCode() async {
        isLoading = true
        resetReferralData()
        nameErrorCheck(code: referralCode, forReferralCode: true)

        guard referralAvailabilityErrorMessage == nil else {
            isLoading = false
            return
        }

        await checkNameAvailability(code: referralCode)
    }

    // MARK: - Network — fees

    func calculateFees() async {
        isFeesLoading = true
        do {
            let info = try await thorchainService.getNetwork()
            registrationFee = info.tns_register_fee_rune.toDecimal()
            feePerBlock = info.tns_fee_per_block_rune.toDecimal()
        } catch {
            logger.error("calculateFees failed: \(error.localizedDescription)")
        }
        isFeesLoading = false
    }

    // MARK: - Network — gas

    func loadGasInfo() async {
        guard let nativeCoin else { return }
        do {
            let request = SendChainSpecificRequest(
                coin: nativeCoin,
                toAddress: nativeCoin.address,
                amount: .zero,
                memo: nil,
                sendMaxAmount: false,
                isDeposit: true,
                transactionType: .unspecified,
                gasLimit: nil,
                feeMode: .default,
                fromAddress: nativeCoin.address
            )
            let chainSpecific = try await interactor.fetchChainSpecific(request)
            gas = chainSpecific.gas
        } catch {
            logger.error("loadGasInfo failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Network — referral data

    func fetchReferralCodeDetails() async {
        isLoading = true
        defer { isLoading = false }

        guard savedReferralCode.isNotEmpty else { return }

        do {
            let details = try await thorchainService.getThornameDetails(name: savedReferralCode)
            let lastBlock = try await thorchainService.getLastBlock()
            let formattedExpires = ReferralExpiryDataCalculator.getFormattedExpiryDate(
                expiryBlock: details.expireBlockHeight,
                currentBlock: lastBlock
            )
            let runes = await calculateCollectedRewards(details: details)
            currentBlockheight = lastBlock
            expiresOn = formattedExpires
            collectedRewards = runes
            thornameDetails = details
        } catch {
            expiresOn = "-"
            collectedRewards = "-"
        }
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
            let preferredAsset = try? await thorchainService.getPoolAsset(asset: details.preferredAsset)
            guard let preferredAsset else { return "" }
            assetDecimals = preferredAsset.decimals ?? 6
            assetMultiplier = preferredAsset.assetTorPrice.toDecimal() / 100_000_000
            assetTicker = String(preferredAsset.asset.split(separator: ".")[1].split(separator: "-").first ?? "")
        }

        let collectedRunesAmount = details.affiliateCollectorRune.toDecimal()
        let collectedAssetAmount = collectedRunesAmount * assetMultiplier / pow(10, assetDecimals)
        return "\(collectedAssetAmount.formatForDisplay()) \(assetTicker)"
    }

    func fetchVaultData() async {
        isLoading = true
        defer { isLoading = false }

        guard vault.referralCode == nil,
              let thorAddress = vault.nativeCoin(for: .thorChain)?.address
        else { return }

        let thorname = try? await thorchainService.getAddressLookup(address: thorAddress)
        guard let thorname, !thorname.isEmpty else { return }

        let normalised = thorname.uppercased()
        let referral = ReferralCode(code: normalised, vault: vault)
        saveReferralCode(referral)
    }

    // MARK: - Verify + boundary

    /// Verifies the referral inputs and returns the immutable `SendTransaction`
    /// to navigate with. Returns `nil` and shows an alert if validation fails.
    func verifyReferralEntries() async -> SendTransaction? {
        await verifyReferralCode()

        guard isReferralCodeVerified else {
            showAlert(with: "pickValidCode")
            return nil
        }

        guard enoughGas() else {
            showAlert(with: "insufficientBalance")
            return nil
        }

        return buildSendTransaction()
    }

    /// Constructs the immutable `SendTransaction` from current VM state.
    /// Returns `nil` if the native coin hasn't been resolved (vault doesn't
    /// hold RUNE) — callers should guard before calling.
    func buildSendTransaction() -> SendTransaction? {
        guard let nativeCoin else { return nil }

        let memo = "~:\(referralCode.uppercased()):THOR:\(nativeCoin.address):\(nativeCoin.address)"
        let base = SendTransaction.empty(coin: nativeCoin, vault: vault)
        return base.copy(
            fromAddress: nativeCoin.address,
            amount: totalFee.formatDecimalToLocale(),
            memo: memo,
            gas: gas,
            transactionType: .unspecified,
            memoFunctionDictionary: ["memo": ""]
        )
    }

    func persistReferralCode(_ code: String) {
        if let vaultReferral = vault.referralCode {
            vaultReferral.code = code
            do {
                try Storage.shared.save()
            } catch {
                showNameError(with: "systemErrorMessage")
            }
        } else {
            // `saveReferralCode` already handles insert + save.
            let referral = ReferralCode(code: code, vault: vault)
            saveReferralCode(referral)
        }
    }

    // MARK: - Private

    private func enoughGas() -> Bool {
        guard let nativeCoin else { return false }
        let decimals = nativeCoin.decimals
        let gasDecimal = Decimal(gas) / pow(10, decimals)
        let amount = totalFee + gasDecimal
        let vaultAmount = nativeCoin.balanceDecimal
        return vaultAmount >= amount
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

    private func markCodeVerified() {
        isReferralCodeVerified = true
        availabilityStatus = .available
        isLoading = false
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
            _ = try await thorchainService.getThornameLookup(name: code)
            showNameError(with: "alreadyTaken")
        } catch {
            guard error as? THORChainAPIError == .thornameNotFound else {
                showNameError(with: "systemErrorMessage")
                return
            }
            markCodeVerified()
        }
    }

    private func containsWhitespace(_ text: String) -> Bool {
        text.rangeOfCharacter(from: .whitespacesAndNewlines) != nil
    }

    @MainActor
    private static func defaultSaveReferralCode(_ referral: ReferralCode) {
        Storage.shared.insert(referral)
        try? Storage.shared.save()
    }
}
