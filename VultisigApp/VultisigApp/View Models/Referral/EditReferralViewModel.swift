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
    @Published var preferredAsset: PreferredAsset?

    @AppStorage("savedGeneratedReferralCode") var savedGeneratedReferralCode: String = ""
    let thornameDetails: THORName
    let currentBlockHeight: UInt64
    
    var totalFeeAmountText: String {
        "\(totalFeeAmount) RUNE"
    }
    
    var totalFeeFiatAmountText: String {
        let fiatAmount = RateProvider.shared.fiatBalance(value: totalFeeAmount, coin: nativeCoin)
        return fiatAmount.formatToFiat(includeCurrencySymbol: true, useAbbreviation: true)
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
    
    func setup(tx: SendTransaction) async {
        let feePerBlockString = (try? await thorchainService.getNetworkInfo())?.tns_fee_per_block_rune ?? ""
        await MainActor.run {
            self.feePerBlock = Decimal(string: feePerBlockString) ?? 0
            self.preferredAsset = PreferredAssetFactory.createCoin(from: thornameDetails.preferredAsset)
        }
    }
    
    func verifyReferralEntries(tx: SendTransaction) async -> Bool {
        guard enoughGas(tx: tx) else {
            await MainActor.run {
                errorMessage = "insufficientBalance"
                hasError = true
            }
            
            return false
        }
        
        await createTransaction(tx: tx, preferredAsset: preferredAsset)
        return true
    }
}

private extension EditReferralViewModel {
    func enoughGas(tx: SendTransaction) -> Bool {
        let decimals = tx.coin.decimals
        let gas = Decimal(tx.gas) / pow(10,decimals)
        let amount = totalFeeAmount + gas
        let vaultAmount = nativeCoin.balanceDecimal
        
        return vaultAmount >= amount
    }
    
    @MainActor
    func createTransaction(tx: SendTransaction, preferredAsset: PreferredAsset?) async {
        var preferredAssetCoin: Coin?
        if let preferredAsset {
            preferredAssetCoin = try? await CoinService.addToChain(asset: preferredAsset.asset, to: vault, priceProviderId: preferredAsset.asset.priceProviderId)
        }
        
        tx.amount = totalFeeAmount.formatDecimalToLocale()
        
        let fnCallInstance = FunctionCallInstance.custom(FunctionCallCustom())
        tx.memoFunctionDictionary = fnCallInstance.toDictionary()
        tx.transactionType = fnCallInstance.getTransactionType()
        
        
        let memo = ReferralCodeMemoFactory.createEdit(
            referralCode: savedGeneratedReferralCode,
            nativeCoin: nativeCoin,
            preferredAsset: preferredAsset,
            preferredAssetCoin: preferredAssetCoin
        )
        
        print("Memo: \(memo)")
        tx.memo = memo
        tx.coin = nativeCoin
        tx.fromAddress = nativeCoin.address
    }
}

enum ReferralCodeMemoFactory {
    static func createEdit(referralCode: String, nativeCoin: Coin, preferredAsset: PreferredAsset?, preferredAssetCoin: Coin?) -> String {
        var preferredAssetAddressPart = ":THOR"
        var preferredAssetPart = ""
        if let preferredAsset, let preferredAssetCoin {
            preferredAssetAddressPart = ":\(preferredAsset.asset.chain.swapAsset):\(preferredAssetCoin.address)"
            preferredAssetPart = ":\(preferredAsset.thorchainAsset)"
        }
        
        return "~:\(referralCode.uppercased())\(preferredAssetAddressPart):\(nativeCoin.address)\(preferredAssetPart)"
    }
}
