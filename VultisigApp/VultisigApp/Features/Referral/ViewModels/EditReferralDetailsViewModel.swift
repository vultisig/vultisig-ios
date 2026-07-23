//
//  EditReferralDetailsViewModel.swift
//  VultisigApp
//
//  Form-state-on-VM rewrite of the Referral edit flow. Owns every form
//  field directly (replacing the legacy `FunctionCallForm`'s `@Published`
//  fields threaded via `tx:` parameters) and produces an immutable
//  `SendTransaction` only on Continue via `buildSendTransaction()`.
//
//  Replaces `EditReferralViewModel`. Mirrors `ReferralDetailsViewModel`'s
//  shape for the edit flow's narrower form (extended-count + preferred
//  asset choice).
//

import BigInt
import Foundation
import OSLog
import SwiftUI
import VultisigCommonData

@MainActor
@Observable
final class EditReferralDetailsViewModel {

    @ObservationIgnored private let logger = Logger(subsystem: "com.vultisig.app", category: "edit-referral-details-vm")
    @ObservationIgnored private let interactor: SendInteractor
    @ObservationIgnored private let thorchainService: THORChainAPIService
    @ObservationIgnored private let addCoinIfNeeded: @MainActor (THORChainAsset, Vault) throws -> Coin?

    // MARK: - Identity (immutable once set)
    let nativeCoin: Coin
    let vault: Vault
    let thornameDetails: THORName
    let currentBlockHeight: UInt64

    // MARK: - Form fields
    var extendedCount: Int = 0
    var preferredAsset: THORChainAsset?
    var initialPreferredAsset: THORChainAsset?

    // MARK: - Async state
    var loadingFees: Bool = false
    var errorMessage: String?
    var hasError: Bool = false

    // MARK: - Network-sourced
    var feePerBlock: Decimal = 0

    // MARK: - Send-transaction props
    var gas: BigInt = .zero

    // MARK: - Init

    init(
        nativeCoin: Coin,
        vault: Vault,
        thornameDetails: THORName,
        currentBlockHeight: UInt64,
        interactor: SendInteractor = DefaultSendInteractor.live,
        thorchainService: THORChainAPIService = THORChainAPIService(),
        addCoinIfNeeded: @escaping @MainActor (THORChainAsset, Vault) throws -> Coin? = EditReferralDetailsViewModel.defaultAddCoinIfNeeded
    ) {
        self.nativeCoin = nativeCoin
        self.vault = vault
        self.thornameDetails = thornameDetails
        self.currentBlockHeight = currentBlockHeight
        self.interactor = interactor
        self.thorchainService = thorchainService
        self.addCoinIfNeeded = addCoinIfNeeded
    }

    // MARK: - Derived state

    var referralCode: String {
        thornameDetails.name.uppercased()
    }

    var totalFeeAmount: Decimal {
        let amount = feePerBlock * Decimal(ReferralExpiryDataCalculator.blockPerYear * UInt64(extendedCount))
        return amount / 100_000_000
    }

    var totalFeeAmountText: String {
        "\(totalFeeAmount) RUNE"
    }

    var totalFeeFiatAmountText: String {
        let fiatAmount = RateProvider.shared.fiatBalance(value: totalFeeAmount, coin: nativeCoin)
        return fiatAmount.formatToFiat(includeCurrencySymbol: true)
    }

    var extendedExpirationDate: String {
        ReferralExpiryDataCalculator.getFormattedExpiryDate(
            expiryBlock: thornameDetails.expireBlockHeight,
            currentBlock: currentBlockHeight,
            extendedByYears: extendedCount
        )
    }

    var isValidForm: Bool {
        extendedCount > 0 || preferredAsset != initialPreferredAsset
    }

    // MARK: - Setup

    func setup() async {
        // Preferred-asset comes from `thornameDetails` (already in memory) — keep
        // it outside the throwing path so a fee-fetch failure doesn't leave both
        // nil and have `buildSendTransaction()` drop the current asset on retry.
        preferredAsset = PreferredAssetFactory.createCoin(from: thornameDetails.preferredAsset)
        initialPreferredAsset = preferredAsset

        loadingFees = true
        defer { loadingFees = false }
        do {
            let fee = try await thorchainService.getNetwork().tns_fee_per_block_rune.toDecimal()
            feePerBlock = fee
        } catch {
            showError(message: "referralNetworkError")
        }
    }

    // MARK: - Network — gas

    // MARK: - Verify + boundary

    /// Verifies edit inputs and returns the immutable `SendTransaction` to
    /// navigate with. Returns `nil` and shows an inline error if validation
    /// fails.
    func verifyReferralEntries() -> SendTransaction? {
        guard enoughGas() else {
            showError(message: "insufficientBalance")
            return nil
        }
        return buildSendTransaction()
    }

    /// Constructs the immutable `SendTransaction` from current VM state.
    func buildSendTransaction() -> SendTransaction {
        var preferredAssetCoin: Coin?
        if let preferredAsset {
            preferredAssetCoin = try? addCoinIfNeeded(preferredAsset, vault)
        }

        let memo = ReferralCodeMemoFactory.createEdit(
            referralCode: referralCode,
            nativeCoin: nativeCoin,
            preferredAsset: preferredAsset,
            preferredAssetCoin: preferredAssetCoin
        )

        let base = SendTransaction.empty(coin: nativeCoin, vault: vault)
        return base.copy(
            fromAddress: nativeCoin.address,
            amount: totalFeeAmount.formatDecimalToLocale(),
            memo: memo,
            gas: gas,
            transactionType: .unspecified,
            memoFunctionDictionary: ["memo": ""]
        )
    }

    // MARK: - Private

    private func enoughGas() -> Bool {
        let decimals = nativeCoin.decimals
        let gasDecimal = Decimal(gas) / pow(10, decimals)
        let amount = totalFeeAmount + gasDecimal
        let vaultAmount = nativeCoin.balanceDecimal
        return vaultAmount >= amount
    }

    private func showError(message: String) {
        errorMessage = message.localized
        hasError = true
    }

    @MainActor
    private static func defaultAddCoinIfNeeded(_ asset: THORChainAsset, _ vault: Vault) throws -> Coin? {
        try CoinService.addIfNeeded(
            asset: asset.asset,
            to: vault,
            priceProviderId: asset.asset.priceProviderId
        )
    }
}
