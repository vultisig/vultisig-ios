//
//  CircleYieldProvider.swift
//  VultisigApp
//

import Foundation
import BigInt
import VultisigCommonData

/// Adapts the existing Circle MSCA withdraw/deposit flow to `DefiYieldProvider`.
///
/// Behavior-preserving: withdraws still build the native-ETH MSCA
/// `execute(USDC, 0, transfer(vault, amount))` payload (calldata in `memo`),
/// so the verify/keysign path is unchanged. Circle redemptions are instant —
/// there is no queue — so `buildRequestRedeemPayload` maps to `withdraw` and
/// there is no separate claim step.
struct CircleYieldProvider: DefiYieldProvider {
    let id: DefiYieldProviderID = .circle

    private let logic = CircleViewLogic()
    private let storage = YieldPositionStorageService()

    var chain: Chain { CircleViewLogic.getChainDetails().chain }
    var assetContract: String { CircleViewLogic.getChainDetails().usdcContract }
    var requiresAccountSetup: Bool { true }
    var depositsEnabled: Bool { CircleConstants.depositsEnabled }
    var hasWindowedRedemption: Bool { false }
    var assetDecimals: Int { 6 }
    // Circle deposits are disabled (funded via MSCA, not a vault call), so this
    // recipient is never reached; the USDC contract is a safe placeholder.
    var depositRecipient: String { assetContract }

    var presentation: YieldPresentation {
        YieldPresentation(
            titleKey: "circleTitle",
            dashboardTitleKey: "circleDashboardDeposited",
            dashboardDescriptionKey: "circleDashboardDepositDescription",
            depositedLabelKey: "circleUSDCDeposited",
            depositButtonKey: "circleDashboardDeposit",
            withdrawButtonKey: "circleDashboardWithdraw",
            depositTitleKey: "circleDepositTitle",
            withdrawTitleKey: "circleWithdrawTitle",
            withdrawAmountLabelKey: "circleWithdrawAmountLabel",
            withdrawBalanceAvailableKey: "circleDepositBalanceAvailable",
            withdrawConfirmKey: "circleWithdrawConfirm",
            ethRequiredKey: "circleDashboardETHRequired",
            ethereumRequiredTitleKey: "circleEthereumRequired",
            ethereumRequiredDescriptionKey: "circleEthereumRequiredDescription",
            apyLabelKey: "circleAPYLabel",
            sharesTicker: "USDC",
            showsRedemptionRows: false,
            staticApyText: "circleStaticApy".localized,
            providerNameKey: "circleTitle",
            bannerLogoAsset: "circle-defi-banner",
            infoBannerKey: "circleDashboardInfoText",
            rowLogoAsset: "circle-logo",
            rowTitleKey: "circleTitle",
            rowSubtitleKey: "circleRowYieldAccount",
            setupBalanceLabelKey: "circleSetupAccountBalance",
            setupCreatingAccountKey: "circleCreatingAccount",
            setupOpenAccountKey: "circleSetupOpenAccount"
        )
    }

    // MARK: - Account lifecycle

    func resolveAccountAddress(vault: Vault) async throws -> String? {
        if let existing = vault.circleWalletAddress, !existing.isEmpty {
            return existing
        }
        return try await logic.checkExistingWallet(vault: vault)
    }

    func createAccount(vault: Vault) async throws -> String {
        try await logic.createWallet(vault: vault)
    }

    /// Stores the resolved MSCA address so the DeFi row, gating, and refresh path
    /// can read it back. Runs on the main actor (the vault is a SwiftData model).
    @MainActor
    func persistAccountAddress(_ address: String, vault: Vault) {
        guard !address.isEmpty else { return }
        vault.circleWalletAddress = address
    }

    @MainActor
    func isAccountProvisioned(vault: Vault) -> Bool {
        vault.circleWalletAddress?.isEmpty == false
    }

    // MARK: - Reads

    func refreshPosition(vault: Vault) async throws -> YieldVaultPosition {
        let (usdcBalance, ethBalance) = try await logic.refresh(vault: vault)
        try await MainActor.run {
            try storage.upsert(
                providerID: id,
                depositedBalance: usdcBalance,
                nativeGasBalance: ethBalance,
                redemptions: [],
                for: vault
            )
        }
        return YieldVaultPosition(
            depositedBalance: usdcBalance,
            nativeGasBalance: ethBalance,
            redemptions: [],
            lastUpdated: .now
        )
    }

    func buildRequestRedeemPayload(vault: Vault, recipient: String, amount: BigInt) async throws -> KeysignPayload {
        // Circle is instant — a redemption request is just the withdraw.
        try await withdrawalPayload(vault: vault, recipient: recipient, amount: amount)
    }

    func buildWithdrawPayload(vault: Vault, recipient: String, amount: BigInt) async throws -> KeysignPayload {
        try await withdrawalPayload(vault: vault, recipient: recipient, amount: amount)
    }

    /// Builds the MSCA withdrawal payload, deploying the wallet on demand: a
    /// first-time withdraw can hit an undeployed MSCA, so on `walletNotDeployed`
    /// we provision it via the proxy and retry once.
    private func withdrawalPayload(vault: Vault, recipient: String, amount: BigInt) async throws -> KeysignPayload {
        do {
            return try await logic.getWithdrawalPayload(vault: vault, recipient: recipient, amount: amount)
        } catch CircleServiceError.walletNotDeployed {
            // Provision the MSCA, then retry once. A real provisioning failure
            // now surfaces to the user instead of a confusing second
            // `walletNotDeployed`.
            _ = try await CircleApiService.shared.createWallet(ethAddress: recipient)
            return try await logic.getWithdrawalPayload(vault: vault, recipient: recipient, amount: amount)
        }
    }

    // The remaining requirements are intentionally trivial for Circle: it has
    // no public APY/TVL feed, withdraws are synchronous MSCA transfers (always
    // instant), deposits flow through MSCA creation rather than a vault call,
    // and there is no separate claim step.
    // swiftlint:disable unused_parameter async_without_await

    func apy(vault: Vault) async throws -> Decimal? { nil }

    func tvl() async throws -> Decimal? { nil }

    func canWithdrawInstantly(vault: Vault, amount: BigInt) async -> Bool { true }

    func buildDepositPayload(vault: Vault, amount: BigInt) async throws -> KeysignPayload {
        throw CircleServiceError.keysignError("circleDepositsDisabled".localized)
    }

    func buildClaimPayload(vault: Vault, recipient: String, redemption: YieldRedemption) async throws -> KeysignPayload {
        throw CircleServiceError.keysignError("circleNoSeparateClaimStep".localized)
    }

    // swiftlint:enable unused_parameter async_without_await
}
