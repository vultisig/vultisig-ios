//
//  YieldVaultView.swift
//  VultisigApp
//

import OSLog
import SwiftUI
import BigInt

private let logger = Logger(subsystem: "com.vultisig.app", category: "yield-vault-view")

/// Generic yield-vault dashboard, parameterized by a `DefiYieldProvider`.
/// Renders the deposited balance, APY / next-redemption / shares-ticker rows,
/// Deposit / Withdraw actions, and the windowed-redemption state (pending copy
/// + a Claim CTA when a redemption has settled).
struct YieldVaultView: View {
    let vault: Vault

    @StateObject private var model: YieldViewModel
    @Environment(\.router) private var router

    init(vault: Vault, providerID: DefiYieldProviderID) {
        self.vault = vault
        _model = StateObject(wrappedValue: YieldViewModel(providerID: providerID))
    }

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
        .screenTitle("noonTitle".localized)
        .onLoad {
            Task { await onAppear() }
        }
    }

    // MARK: - Dashboard

    private var dashboard: some View {
        ScrollView {
            VStack(spacing: NoonConstants.Design.verticalSpacing) {
                headerDescription
                positionCard
            }
            .padding(.top, NoonConstants.Design.mainViewTopPadding)
            .padding(.bottom, NoonConstants.Design.mainViewBottomPadding)
            .padding(.horizontal, NoonConstants.Design.horizontalPadding)
        }
        .background(VaultMainScreenBackground())
        #if os(iOS)
        .refreshable { await refresh() }
        #endif
    }

    private var headerDescription: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("noonDashboardTitle".localized)
                .font(Theme.fonts.bodyLMedium)
                .foregroundStyle(Theme.colors.textPrimary)
            Text("noonDashboardDescription".localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var positionCard: some View {
        VStack(spacing: 16) {
            depositedSection
            Separator(color: Theme.colors.borderLight, opacity: 1)
            infoRows
            actionButtons

            if let pending = model.pendingRedemption {
                pendingRedemptionSection(pending)
            }
            if let claimable = model.claimableRedemption {
                claimableRedemptionSection(claimable)
            }
        }
        .padding(NoonConstants.Design.cardPadding)
        .background(cardBackground)
    }

    private var depositedSection: some View {
        HStack(spacing: 12) {
            Image("usdc")
                .resizable()
                .frame(width: 40, height: 40)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("noonUSDCDeposited".localized)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textSecondary)
                HiddenBalanceText(AmountFormatter.formatCryptoAmount(value: model.depositedBalance, ticker: "USDC"))
                    .font(Theme.fonts.priceTitle1)
                    .foregroundStyle(Theme.colors.textPrimary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var infoRows: some View {
        VStack(spacing: 12) {
            infoRow(
                icon: "divide.circle",
                label: "noonAPYLabel".localized,
                value: apyText,
                valueColor: Theme.colors.alertSuccess
            )
            infoRow(
                icon: "calendar",
                label: "noonNextRedemption".localized,
                value: nextRedemptionText,
                valueColor: Theme.colors.textPrimary
            )
            infoRow(
                icon: "dollarsign.circle",
                label: "noonSharesTicker".localized,
                value: "naccUSDC",
                valueColor: Theme.colors.textPrimary
            )
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
        HStack(spacing: 0) {
            DefiButton(
                title: "noonWithdraw".localized,
                icon: "minus.circle",
                type: .outline,
                isSystemIcon: true,
                action: { router.navigate(to: YieldRoute.withdraw(vault: vault, providerID: model.providerID, model: model)) }
            )
            .disabled(model.depositedBalance <= 0)

            Spacer()

            DefiButton(
                title: "noonDeposit".localized,
                icon: "plus.circle",
                isSystemIcon: true,
                action: { router.navigate(to: YieldRoute.deposit(vault: vault, providerID: model.providerID)) }
            )
            .disabled(!model.provider.depositsEnabled)
        }
    }

    // MARK: - Redemption states

    private func pendingRedemptionSection(_ redemption: YieldRedemption) -> some View {
        VStack(spacing: 12) {
            Separator(color: Theme.colors.borderLight, opacity: 1)
            redemptionBanner("noonRedemptionPending".localized)
            Text(claimAvailabilityText(redemption))
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func claimableRedemptionSection(_ redemption: YieldRedemption) -> some View {
        VStack(spacing: 12) {
            Separator(color: Theme.colors.borderLight, opacity: 1)
            redemptionBanner("noonRedemptionClaimable".localized)
            PrimaryButton(title: "noonClaim".localized) {
                Task { await handleClaim(redemption) }
            }
            .disabled(model.nativeGasBalance <= 0)
        }
    }

    private func redemptionBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(Theme.colors.textTertiary)
            Text(text)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: NoonConstants.Design.cornerRadius)
            .inset(by: 0.5)
            .stroke(Color(hex: "34E6BF").opacity(0.17))
            .fill(
                LinearGradient(
                    stops: [
                        Gradient.Stop(color: Color(hex: "34E6BF"), location: 0.00),
                        Gradient.Stop(color: Color(red: 0.11, green: 0.5, blue: 0.42).opacity(0), location: 1.00)
                    ],
                    startPoint: UnitPoint(x: 0.5, y: 0),
                    endPoint: UnitPoint(x: 0.5, y: 1)
                ).opacity(0.09)
            )
    }

    private var missingEthState: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundStyle(Theme.colors.alertWarning)
            Text("noonEthereumRequired".localized)
                .font(Theme.fonts.title2)
                .foregroundStyle(Theme.colors.textPrimary)
            Text("noonEthereumRequiredDescription".localized)
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
        guard let apy = model.apy else { return "--" }
        return "\(apy.formatted(.number.precision(.fractionLength(0...2))))%"
    }

    private var nextRedemptionText: String {
        guard let date = NoonYieldProvider.nextSettlementDate() else { return "--" }
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return "\(formatter.string(from: date)) · 23:00 UTC"
    }

    private func claimAvailabilityText(_ redemption: YieldRedemption) -> String {
        guard let claimableAt = redemption.claimableAt else {
            return "noonRedemptionClaimable".localized
        }
        let days = max(0, Calendar.current.dateComponents([.day], from: Date(), to: claimableAt).day ?? 0)
        return String(format: "noonClaimAvailableInDays".localized, days)
    }

    // MARK: - Actions

    private func onAppear() async {
        do {
            model.accountAddress = try await model.provider.resolveAccountAddress(vault: vault)
            model.missingEth = false
        } catch {
            logger.error("Yield account resolve failed: \(error.localizedDescription)")
            model.missingEth = (vault.nativeCoin(for: model.provider.chain) == nil)
        }
        model.hasCheckedAccount = true

        model.seed(from: YieldPositionStorageService().position(for: vault, providerID: model.providerID))
        await refresh()
        await model.loadApy(vault: vault)
    }

    private func refresh() async {
        await model.refresh(vault: vault)
    }

    private func handleClaim(_ redemption: YieldRedemption) async {
        guard let recipient = vault.nativeCoin(for: model.provider.chain)?.address else { return }
        guard let usdcCoin = vault.coins.first(where: { $0.chain == model.provider.chain && $0.ticker == "USDC" }) else { return }

        do {
            let payload = try await model.provider.buildClaimPayload(vault: vault, recipient: recipient, redemption: redemption)
            await MainActor.run {
                let displayTx = SendTransaction.empty(coin: usdcCoin, vault: vault).with(
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
            }
        } catch {
            await MainActor.run { model.error = error }
        }
    }
}
