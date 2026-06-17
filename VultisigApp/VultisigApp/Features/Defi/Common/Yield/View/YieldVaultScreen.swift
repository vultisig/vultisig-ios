//
//  YieldVaultScreen.swift
//  VultisigApp
//

import OSLog
import SwiftUI
import BigInt

private let logger = Logger(subsystem: "com.vultisig.app", category: "yield-vault-view")

/// Generic yield-vault dashboard, parameterized by a `DefiYieldProvider`. Both
/// Circle (MSCA, account-gated, instant) and Noon (direct-EOA, windowed) render
/// through this one screen; provider-specific copy / logo / chrome come from
/// `presentation` and account-gated providers show an "Open Account" setup card
/// until their account resolves. Renders the top banner (provider + USD value +
/// logo), the underlined "Deposited" tab + description, a dismissible info
/// banner, the position card, APY / next-redemption / shares rows, Deposit /
/// Withdraw actions, and the windowed-redemption state.
struct YieldVaultScreen: View {
    @ObservedObject var vault: Vault

    @StateObject private var model: YieldViewModel
    @Environment(\.router) private var router

    /// Per-vault, per-provider persisted dismissal for the empty-state info banner.
    @AppStorage private var infoBannerDismissed: Bool

    init(vault: Vault, providerID: DefiYieldProviderID) {
        self.vault = vault
        _model = StateObject(wrappedValue: YieldViewModel(providerID: providerID))
        _infoBannerDismissed = AppStorage(
            wrappedValue: false,
            "yieldInfoBannerDismissed_\(providerID.rawValue)_\(vault.pubKeyECDSA)"
        )
    }

    private var presentation: YieldPresentation { model.presentation }

    var body: some View {
        Screen {
            if !model.hasCheckedAccount {
                ProgressView()
                    .progressViewStyle(.circular)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.missingEth {
                missingEthState
            } else {
                dashboard
            }
        }
        .screenTitle(presentation.titleKey.localized)
        .onLoad {
            Task { await onAppear() }
        }
    }

    // MARK: - Dashboard

    private var dashboard: some View {
        ScrollView {
            VStack(spacing: 16) {
                topBanner
                headerDescription
                if !model.hasAccount, !infoBannerDismissed {
                    infoBanner
                }
                if model.hasAccount {
                    positionCard
                } else {
                    setupCard
                }
            }
            .padding(.top, dashboardTopPadding)
            .padding(.bottom, 32)
        }
        .background(VaultMainScreenBackground())
        #if os(iOS)
        .refreshable { await refresh() }
        #endif
    }

    private var topBanner: some View {
        YieldTopBanner(
            providerName: presentation.providerNameKey.localized,
            usdValue: model.depositedBalance.formatToFiat(),
            logoAsset: presentation.bannerLogoAsset,
            tabTitle: presentation.dashboardTitleKey.localized
        )
    }

    private var headerDescription: some View {
        Text(presentation.dashboardDescriptionKey.localized)
            .font(Theme.fonts.caption12)
            .foregroundStyle(Theme.colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var infoBanner: some View {
        InfoBannerView(
            description: presentation.infoBannerKey.localized,
            type: .info,
            leadingIcon: nil,
            onClose: {
                withAnimation { infoBannerDismissed = true }
            }
        )
    }

    private var positionCard: some View {
        VStack(spacing: 16) {
            depositedSection
            Separator(color: Theme.colors.borderLight, opacity: 1)
            infoRows
            actionButtons

            ForEach(model.pendingRedemptions) { pending in
                pendingRedemptionSection(pending)
            }
            ForEach(model.claimableRedemptions) { claimable in
                claimableRedemptionSection(claimable)
            }
            if model.showsWindowedNote {
                windowedNoteSection
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private var windowedNoteSection: some View {
        VStack(spacing: 12) {
            Separator(color: Theme.colors.borderLight, opacity: 1)
            redemptionBanner(presentation.redemptionWindowNoteKey.localized, color: Theme.colors.alertWarning)
        }
    }

    private var depositedSection: some View {
        HStack(spacing: 12) {
            Image(presentation.assetLogoAsset)
                .resizable()
                .frame(width: 48, height: 48)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.depositedLabelKey.localized)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textTertiary)
                HiddenBalanceText(AmountFormatter.formatCryptoAmount(value: model.depositedBalance, ticker: presentation.assetTicker))
                    .font(Theme.fonts.priceTitle1)
                    .foregroundStyle(Theme.colors.textPrimary)
                HiddenBalanceText(model.depositedBalance.formatToFiat())
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var infoRows: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "divide.circle")
                    Text(presentation.apyLabelKey.localized)
                        .font(Theme.fonts.bodySMedium)
                }
                .foregroundStyle(Theme.colors.textTertiary)
                Spacer()
                Text(apyText)
                    .font(Theme.fonts.bodyMMedium)
                    .foregroundStyle(Theme.colors.alertSuccess)
            }
            if presentation.showsRedemptionRows {
                infoRow(
                    icon: "calendar",
                    label: presentation.nextRedemptionLabelKey.localized,
                    value: nextRedemptionText,
                    valueColor: Theme.colors.textPrimary
                )
                infoRow(
                    icon: "dollarsign.circle",
                    label: presentation.sharesTickerLabelKey.localized,
                    value: presentation.sharesTicker,
                    valueColor: Theme.colors.textPrimary
                )
            }
        }
    }

    private func infoRow(icon: String, label: String, value: String, valueColor: Color) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(label)
                    .font(Theme.fonts.bodySMedium)
            }
            .foregroundStyle(Theme.colors.textTertiary)
            Spacer()
            Text(value)
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(valueColor)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 16) {
            if model.depositedBalance > 0 {
                DefiButton(
                    title: presentation.withdrawButtonKey.localized,
                    icon: "minus.circle",
                    type: .outline,
                    isSystemIcon: true,
                    action: { router.navigate(to: YieldRoute.withdraw(vault: vault, providerID: model.providerID, model: model)) }
                )
            }

            DefiButton(
                title: presentation.depositButtonKey.localized,
                icon: "plus.circle",
                isSystemIcon: true,
                action: { router.navigate(to: YieldRoute.deposit(vault: vault, providerID: model.providerID)) }
            )
            .disabled(!model.provider.depositsEnabled)
        }
    }

    // MARK: - Setup card (account-gated providers, e.g. Circle MSCA)

    private var setupCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(presentation.assetLogoAsset)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("circleSetupAccountBalance".localized)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textSecondary)
                    Text(AmountFormatter.formatCryptoAmount(value: model.depositedBalance, ticker: presentation.assetTicker))
                        .font(Theme.fonts.priceBodyL)
                        .foregroundStyle(Theme.colors.textPrimary)
                }
                Spacer()
            }

            PrimaryButton(
                title: setupButtonTitle,
                isLoading: model.isLoading,
                type: .primary,
                size: .medium
            ) {
                Task { await model.createAccount(vault: vault) }
            }
            .disabled(model.isLoading || !model.provider.depositsEnabled)
        }
        .padding(16)
        .background(cardBackground)
    }

    private var setupButtonTitle: String {
        model.isLoading
            ? "circleCreatingAccount".localized
            : "circleSetupOpenAccount".localized
    }

    // MARK: - Redemption states

    private func pendingRedemptionSection(_ redemption: YieldRedemption) -> some View {
        VStack(spacing: 12) {
            Separator(color: Theme.colors.borderLight, opacity: 1)
            redemptionBanner(presentation.redemptionPendingKey.localized, color: Theme.colors.alertWarning)
            Text(claimAvailabilityText(redemption))
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textButtonDisabled)
                .frame(maxWidth: .infinity, alignment: .center)
            if presentation.supportsCancel {
                cancelButton(redemption)
            }
        }
    }

    private func claimableRedemptionSection(_ redemption: YieldRedemption) -> some View {
        VStack(spacing: 12) {
            Separator(color: Theme.colors.borderLight, opacity: 1)
            redemptionBanner(presentation.redemptionClaimableKey.localized, color: Theme.colors.alertSuccess)
            PrimaryButton(title: claimButtonTitle(redemption)) {
                Task { await handleClaim(redemption) }
            }
            .disabled(model.nativeGasBalance <= 0)
            if presentation.supportsCancel {
                cancelButton(redemption)
            }
        }
    }

    /// Per-pending-row Cancel action (VULT's `cancelUnstake`), restoring the
    /// escrowed balance. Only rendered when the provider supports cancel.
    private func cancelButton(_ redemption: YieldRedemption) -> some View {
        PrimaryButton(title: cancelButtonTitle(redemption), type: .secondary) {
            Task { await handleCancel(redemption) }
        }
        .disabled(model.nativeGasBalance <= 0)
    }

    private func redemptionBanner(_ text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Icon(named: "circle-info", color: color, size: 16)
            Text(text)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    /// Extra top inset on macOS to clear the window title bar.
    private var dashboardTopPadding: CGFloat {
        #if os(macOS)
        60
        #else
        16
        #endif
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 24)
            .inset(by: 0.5)
            .fill(Theme.colors.bgSurface1)
            .stroke(Theme.colors.borderLight, lineWidth: 1)
    }

    private var missingEthState: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundStyle(Theme.colors.alertWarning)
            Text(presentation.ethereumRequiredTitleKey.localized)
                .font(Theme.fonts.title2)
                .foregroundStyle(Theme.colors.textPrimary)
            Text(presentation.ethereumRequiredDescriptionKey.localized)
                .font(Theme.fonts.bodyMRegular)
                .foregroundStyle(Theme.colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Derived text

    private var apyText: String {
        if let staticApy = presentation.staticApyText {
            return staticApy
        }
        guard let apy = model.apy else { return "--" }
        return "\(apy.formatted(.number.precision(.fractionLength(0...2))))%"
    }

    /// Windowed-vault "Next redemption" value. Noon computes a weekly settlement
    /// window; VULT reads each request's own on-chain maturity, so when the
    /// provider doesn't use a computed window we fall back to the per-request
    /// `claimableAt` (or "--" when there's no in-flight request).
    private var nextRedemptionText: String {
        if presentation.usesComputedSettlementWindow {
            guard let date = NoonYieldProvider.nextSettlementDate() else { return "--" }
            return "\(Self.utcDayFormatter.string(from: date)) · 23:00 UTC"
        }
        let next = (model.pendingRedemptions + model.claimableRedemptions)
            .compactMap(\.claimableAt)
            .min()
        guard let date = next else { return "--" }
        return Self.utcDayFormatter.string(from: date)
    }

    private static let utcDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    private func claimButtonTitle(_ redemption: YieldRedemption) -> String {
        let amount = AmountFormatter.formatCryptoAmount(value: redemption.amount, ticker: presentation.assetTicker)
        return String(format: presentation.claimAmountKey.localized, amount)
    }

    private func cancelButtonTitle(_ redemption: YieldRedemption) -> String {
        let amount = AmountFormatter.formatCryptoAmount(value: redemption.amount, ticker: presentation.assetTicker)
        return String(format: presentation.cancelRequestKey.localized, amount)
    }

    private func claimAvailabilityText(_ redemption: YieldRedemption) -> String {
        guard let claimableAt = redemption.claimableAt, Date() < claimableAt else {
            return presentation.redemptionClaimableKey.localized
        }
        let days = max(0, Calendar.current.dateComponents([.day], from: Date(), to: claimableAt).day ?? 0)
        return String(format: presentation.claimAvailableInDaysKey.localized, days)
    }

    // MARK: - Actions

    @MainActor
    private func onAppear() async {
        try? YieldPositionStorageService().migrateCirclePositionIfNeeded(for: vault)

        do {
            let resolved = try await model.provider.resolveAccountAddress(vault: vault)
            if let resolved { model.provider.persistAccountAddress(resolved, vault: vault) }
            model.accountAddress = resolved
            model.missingEth = false
        } catch {
            logger.error("Yield account resolve failed: \(error.localizedDescription)")
            model.missingEth = (vault.nativeCoin(for: model.provider.chain) == nil)
        }
        model.hasCheckedAccount = true

        model.seed(from: YieldPositionStorageService().position(for: vault, providerID: model.providerID))
        if model.hasAccount {
            await refresh()
        }
        await model.loadApy(vault: vault)
    }

    @MainActor
    private func refresh() async {
        // VULT enumerates pending unstakes from our own tx receipts (no
        // eth_getLogs): recover any uncaptured requestIds from history BEFORE the
        // position refresh reads + reconciles the persisted set.
        if model.providerID == .vult {
            await VultPendingRequestReconciler().reconcile(vault: vault)
        }
        await model.refresh(vault: vault)
    }

    /// The coin used for the display-only transaction on the verify screen — the
    /// provider's deposited asset (USDC for Circle/Noon, VULT for staking).
    private var displayCoin: Coin? {
        vault.coins.first { $0.chain == model.provider.chain && $0.ticker == presentation.assetTicker }
            ?? vault.coins.first { $0.chain == model.provider.chain && $0.ticker == "USDC" }
    }

    @MainActor
    private func handleClaim(_ redemption: YieldRedemption) async {
        await routeRedemption(redemption) { provider, recipient in
            try await provider.buildClaimPayload(vault: vault, recipient: recipient, redemption: redemption)
        }
    }

    @MainActor
    private func handleCancel(_ redemption: YieldRedemption) async {
        await routeRedemption(redemption) { provider, recipient in
            try await provider.buildCancelUnstakePayload(vault: vault, recipient: recipient, redemption: redemption)
        }
    }

    /// Builds a redemption payload (claim or cancel) and routes to the shared
    /// verify screen with a display-only transaction in the deposited asset.
    @MainActor
    private func routeRedemption(
        _ redemption: YieldRedemption,
        build: (DefiYieldProvider, String) async throws -> KeysignPayload
    ) async {
        guard let recipient = vault.nativeCoin(for: model.provider.chain)?.address else { return }
        guard let coin = displayCoin else { return }

        do {
            let payload = try await build(model.provider, recipient)
            let displayTx = SendTransaction.empty(coin: coin, vault: vault).with(
                toAddress: recipient,
                amount: redemption.amount.description
            )
            router.navigate(
                to: SendRoute.verify(
                    tx: displayTx,
                    retrySignal: SendRetrySignal(),
                    vault: vault,
                    prebuiltKeysignPayload: payload
                )
            )
        } catch {
            model.error = error
        }
    }
}
