//
//  ReferralViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-13.
//

import SwiftUI
import SwiftData

/// Main-screen view model for the Referral feature. Owns the data shown on
/// `ReferralMainScreen` (saved code, expiry, collected rewards, vault data)
/// and the cold-start vault-data fetch used by `ReferralInitialScreen`. Form
/// state for *creating* and *editing* a referral code lives on
/// `ReferralDetailsViewModel` / `EditReferralDetailsViewModel` (introduced by
/// vultisig-ios#4369 — see [[transaction-model-refactor/function-call-form-elimination-plan]]).
@MainActor
class ReferralViewModel: ObservableObject {
    @Published var isLoading: Bool = false

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

    func fetchReferralCodeDetails() async {
        isLoading = true
        guard savedReferralCode.isNotEmpty else {
            isLoading = false
            return
        }
        do {
            let details = try await thorchainReferralService.getThornameDetails(name: savedReferralCode)
            let lastBlock = try await thorchainReferralService.getLastBlock()
            let expiresOn = ReferralExpiryDataCalculator.getFormattedExpiryDate(expiryBlock: details.expireBlockHeight, currentBlock: lastBlock)
            let collectedRunes = await calculateCollectedRewards(details: details)
            // Saved referral code and vault association
            self.currentBlockheight = lastBlock
            self.expiresOn = expiresOn
            self.collectedRewards = collectedRunes
            self.thornameDetails = details
        } catch {
            self.expiresOn = "-"
            self.collectedRewards = "-"
        }

        isLoading = false
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

    func fetchVaultData() async {
        isLoading = true
        guard
            let currentVault,
            currentVault.referralCode == nil,
            let thorAddress = currentVault.nativeCoin(for: .thorChain)?.address
        else {
            isLoading = false
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
        isLoading = false
    }
}
