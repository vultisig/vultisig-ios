//
//  EditReferralViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 07/08/2025.
//

import BigInt
import SwiftUI

class EditReferralViewModel: ObservableObject {
    @Published var extendedCount: Int = 0
    @Published var loadingFees: Bool = false
    @Published var errorMessage: String?
    @Published var hasError = false
    @Published var preferredAsset: THORChainAsset?
    var initialPreferredAsset: THORChainAsset?

    let thornameDetails: THORName
    let currentBlockHeight: UInt64

    var referralCode: String {
        thornameDetails.name.uppercased()
    }

    var totalFeeAmountText: String {
        "\(totalFeeAmount) RUNE"
    }

    var totalFeeFiatAmountText: String {
        let fiatAmount = RateProvider.shared.fiatBalance(value: totalFeeAmount, coin: nativeCoin)
        return fiatAmount.formatToFiat(includeCurrencySymbol: true)
    }

    var totalFeeAmount: Decimal {
        let amount = (feePerBlock * Decimal(ReferralExpiryDataCalculator.blockPerYear * UInt64(extendedCount)))
        return amount / 100_000_000
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

    private let nativeCoin: Coin
    private let vault: Vault
    private let thorchainService = THORChainAPIService()
    var feePerBlock: Decimal = 0

    init(
        nativeCoin: Coin,
        vault: Vault,
        thornameDetails: THORName,
        currentBlockHeight: UInt64
    ) {
        self.nativeCoin = nativeCoin
        self.vault = vault
        self.thornameDetails = thornameDetails
        self.currentBlockHeight = currentBlockHeight
    }

    func setup() async {
        do {
            let feePerBlock = try await thorchainService.getNetwork().tns_fee_per_block_rune.toDecimal()
            await MainActor.run {
                self.feePerBlock = feePerBlock
                self.preferredAsset = PreferredAssetFactory.createCoin(from: thornameDetails.preferredAsset)
                self.initialPreferredAsset = preferredAsset
            }
        } catch {
            await showError(message: "referralNetworkError")
        }
    }

    func verifyReferralEntries(tx: SendTransaction) async -> Bool {
        guard enoughGas(tx: tx) else {
            await showError(message: "insufficientBalance")
            return false
        }

        await createTransaction(tx: tx, preferredAsset: preferredAsset)
        return true
    }
}

private extension EditReferralViewModel {
    func showError(message: String) async {
        await MainActor.run {
            errorMessage = message
            hasError = true
        }
    }

    func enoughGas(tx: SendTransaction) -> Bool {
        let decimals = tx.coin.decimals
        let gas = Decimal(tx.gas) / pow(10, decimals)
        let amount = totalFeeAmount + gas
        let vaultAmount = nativeCoin.balanceDecimal

        return vaultAmount >= amount
    }

    @MainActor
    func createTransaction(tx: SendTransaction, preferredAsset: THORChainAsset?) {
        var preferredAssetCoin: Coin?
        if let preferredAsset {
            preferredAssetCoin = try? CoinService.addIfNeeded(asset: preferredAsset.asset, to: vault, priceProviderId: preferredAsset.asset.priceProviderId)
        }

        tx.amount = totalFeeAmount.formatDecimalToLocale()

        let fnCallInstance = FunctionCallInstance.custom(FunctionCallCustom(tx: tx, vault: vault))
        tx.memoFunctionDictionary = fnCallInstance.toDictionary()
        tx.transactionType = fnCallInstance.getTransactionType()

        let memo = ReferralCodeMemoFactory.createEdit(
            referralCode: referralCode,
            nativeCoin: nativeCoin,
            preferredAsset: preferredAsset,
            preferredAssetCoin: preferredAssetCoin
        )

        tx.memo = memo
        tx.coin = nativeCoin
        tx.fromAddress = nativeCoin.address
    }
}
