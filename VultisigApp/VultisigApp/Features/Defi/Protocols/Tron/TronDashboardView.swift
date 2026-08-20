//
//  TronDashboardView.swift
//  VultisigApp
//
//  Created for TRON Freeze/Unfreeze integration
//

import SwiftUI

struct TronDashboardView: View {
    @ObservedObject var vault: Vault
    @ObservedObject var model: TronViewModel
    let onRefresh: () async -> Void  // Callback for refresh
    @Environment(\.dismiss) var dismiss
    @Environment(\.router) var router
    @EnvironmentObject var homeViewModel: HomeViewModel

    var walletTrxBalance: Decimal {
        return TronViewLogic.getWalletTrxBalance(vault: vault)
    }

    /// Frozen balance in fiat (using TRX coin price)
    var frozenBalanceFiat: String {
        guard let trxCoin = vault.nativeCoin(for: .tron) else {
            return "$0.00"
        }
        return TronViewLogic.formatFiat(balance: model.totalFrozenBalance, trxPrice: trxCoin.price)
    }

    /// "Claim X TRX" — the sum every expired entry returns in one transaction.
    /// Honors the hide-balance toggle like the amounts in the rows above it.
    var claimButtonTitle: String {
        let amount = homeViewModel.hideVaultBalance
            ? String.hideBalanceText
            : "\(model.claimableBalance.formatted()) TRX"
        return String(format: NSLocalizedString("tronClaimButton", comment: "Claim %@"), amount)
    }

    var canClaimExpiredUnfreezes: Bool {
        TronViewLogic.canClaimExpiredUnfreezes(vault: vault)
    }

    var body: some View {
        ZStack {
            VaultMainScreenBackground()

            VStack(spacing: 0) {
                scrollContent
            }
        }
    }

    var scrollContent: some View {
        ScrollView {
            VStack(spacing: TronConstants.Design.verticalSpacing) {
                topBanner

                resourcesCard

                actionsCard

                if let error = model.error, !(error is CancellationError) && error.localizedDescription.lowercased() != "cancelled" {
                    InfoBannerView(
                        description: error.localizedDescription,
                        type: .error,
                        leadingIcon: nil,
                        onClose: {
                            withAnimation { model.error = nil }
                        }
                    )
                }

                pendingWithdrawalsCard
            }
            .padding(.top, TronConstants.Design.mainViewTopPadding)
            .padding(.bottom, TronConstants.Design.mainViewBottomPadding)
            .padding(.horizontal, TronConstants.Design.horizontalPadding)
        }
        #if os(iOS)
        .refreshable {
            await onRefresh()
        }
        #endif
    }

    var topBanner: some View {
        ZStack(alignment: .trailing) {
            // Background with gradient fill
            cardBackground

            // Decorative circles - large and clipped by the card
            GeometryReader { geometry in
                ZStack {
                    // Outer ring (larger, thinner stroke)
                    Circle()
                        .stroke(Theme.colors.tronRed.opacity(0.25), lineWidth: 2)
                        .frame(width: 160, height: 160)

                    // Inner ring (smaller, thicker stroke)
                    Circle()
                        .stroke(Theme.colors.tronRed.opacity(0.4), lineWidth: 4)
                        .frame(width: 120, height: 120)
                }
                .position(x: geometry.size.width - 50, y: geometry.size.height * 0.75)
            }
            .clipShape(TronConstants.Design.cornerRadius.shape)

            // Content
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("TRON")
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textSecondary)

                    if model.isLoadingBalance {
                        // Skeleton placeholder
                        Theme.radius.xs.shape
                            .fill(Theme.colors.bgSurface1)
                            .frame(width: 120, height: 24)
                            .shimmer()
                    } else {
                        HiddenBalanceText(frozenBalanceFiat)
                            .font(Theme.fonts.priceTitle1)
                            .foregroundStyle(Theme.colors.textPrimary)
                    }
                }
                Spacer()

                // Logo on top of the rings
                Image("tron")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 70, height: 70)
                    .clipShape(Circle())
                    .offset(x: 12, y: 20)
            }
            .padding(TronConstants.Design.cardPadding)
        }
    }

    var cardBackground: some View {
        TronConstants.Design.cornerRadius.shape
            .fill(
                LinearGradient(
                    stops: [
                        Gradient.Stop(color: Theme.colors.tronRed.opacity(0.15), location: 0.00),
                        Gradient.Stop(color: Theme.colors.tronRed.opacity(0), location: 1.00)
                    ],
                    startPoint: UnitPoint(x: 0.5, y: 0),
                    endPoint: UnitPoint(x: 0.5, y: 1)
                )
            )
            .overlay(
                TronConstants.Design.cornerRadius.shape
                    .stroke(Theme.colors.tronRed.opacity(0.3), lineWidth: 1)
            )
    }

    var actionsCard: some View {
        VStack(spacing: 16) {
            // Header: Logo + Title + Fiat Balance
            HStack(spacing: 12) {
                Image("tron")
                    .resizable()
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("tronFreezeTitle", comment: "TRON Freeze"))
                        .font(Theme.fonts.bodyMMedium)
                        .foregroundStyle(Theme.colors.textSecondary)

                    if model.isLoadingBalance {
                        Theme.radius.xs.shape
                            .fill(Theme.colors.bgSurface1)
                            .frame(width: 80, height: 20)
                            .shimmer()
                    } else {
                        HiddenBalanceText(frozenBalanceFiat)
                            .font(Theme.fonts.priceTitle1)
                            .foregroundStyle(Theme.colors.textPrimary)
                    }
                }

                Spacer()
            }

            // Divider
            Divider()
                .overlay(Theme.colors.textSecondary.opacity(0.2))

            // Frozen Balance Section
            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("tronFrozenLabel", comment: "Frozen"))
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textSecondary)

                if model.isLoadingBalance {
                    Theme.radius.xs.shape
                        .fill(Theme.colors.bgSurface1)
                        .frame(width: 100, height: 20)
                        .shimmer()
                } else {
                    HiddenBalanceText("\(model.totalFrozenBalance.formatted()) TRX")
                        .font(Theme.fonts.title2)
                        .foregroundStyle(Theme.colors.textPrimary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Action Buttons - Side by side
            HStack(spacing: 12) {
                DefiButton(
                    title: NSLocalizedString("tronUnfreezeButton", comment: "Unfreeze"),
                    icon: .minus,
                    type: .outline,
                    action: {
                        router.navigate(to: TronRoute.unfreeze(
                            vault: vault,
                            frozenBandwidth: model.frozenBandwidthBalance,
                            frozenEnergy: model.frozenEnergyBalance
                        ))
                    }
                )
                .disabled(!model.canUnfreeze)

                DefiButton(
                    title: NSLocalizedString("tronFreezeButton", comment: "Freeze"),
                    icon: .plus,
                    action: { router.navigate(to: TronRoute.freeze(vault: vault)) }
                )
                .disabled(model.availableBalance <= 0)
            }
        }
        .padding(TronConstants.Design.cardPadding)
        .background(
            TronConstants.Design.cornerRadius.shape
                .fill(Theme.colors.bgSurface1)
        )
        .overlay(
            TronConstants.Design.cornerRadius.shape
                .stroke(Theme.colors.textSecondary.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Resources Card (Bandwidth & Energy)

    var resourcesCard: some View {
        TronResourcesCardView(
            availableBandwidth: model.availableBandwidth,
            totalBandwidth: model.totalBandwidth,
            availableEnergy: model.availableEnergy,
            totalEnergy: model.totalEnergy,
            isLoading: model.isLoadingResources
        )
    }

    @ViewBuilder
    var pendingWithdrawalsCard: some View {
        if model.hasPendingWithdrawals {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(Theme.colors.textSecondary)

                    Text(NSLocalizedString("tronPendingWithdrawals", comment: "Pending Withdrawals"))
                        .font(Theme.fonts.bodyLMedium)
                        .foregroundStyle(Theme.colors.textPrimary)

                    Spacer()

                    HiddenBalanceText("\(model.unfreezingBalance.formatted()) TRX")
                        .font(Theme.fonts.bodyLMedium)
                        .foregroundStyle(Theme.colors.textSecondary)
                }

                Divider()
                    .overlay(Theme.colors.textSecondary.opacity(0.3))

                ForEach(model.pendingWithdrawals) { withdrawal in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HiddenBalanceText("\(withdrawal.amount.formatted()) TRX")
                                .font(Theme.fonts.bodyMRegular)
                                .foregroundStyle(Theme.colors.textPrimary)

                            if withdrawal.isClaimable {
                                Text(NSLocalizedString("tronReadyToClaim", comment: "Ready to claim"))
                                    .font(Theme.fonts.caption12)
                                    .foregroundStyle(Theme.colors.textSecondary)
                            } else {
                                Text(TronViewLogic.withdrawalTimeRemaining(withdrawal.expirationDate))
                                    .font(Theme.fonts.caption12)
                                    .foregroundStyle(Theme.colors.textSecondary)
                            }
                        }

                        Spacer()

                        if withdrawal.isClaimable {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Theme.colors.textSecondary)
                        } else {
                            Image(systemName: "hourglass")
                                .foregroundStyle(Theme.colors.textSecondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // One action for every expired entry: WithdrawExpireUnfreeze
                // sweeps all of them at once, so per-row claims would mislead.
                if model.hasClaimableWithdrawals {
                    if !canClaimExpiredUnfreezes {
                        InfoBannerView(
                            description: "tronClaimFastVaultOnly".localized,
                            type: .warning,
                            leadingIcon: .triangleWarning
                        )
                    }

                    DefiButton(
                        title: claimButtonTitle,
                        icon: .arrowDownFromLine,
                        action: onClaim
                    )
                    .disabled(!canClaimExpiredUnfreezes)
                    .padding(.top, 4)
                }
            }
            .padding(TronConstants.Design.cardPadding)
            .background(
                TronConstants.Design.cornerRadius.shape
                    .fill(Theme.colors.bgSurface1)
            )
        }
    }

    private func onClaim() {
        guard let tx = model.makeClaimTransaction(vault: vault) else { return }
        router.navigate(to: SendRoute.verify(tx: tx, retrySignal: SendRetrySignal(), vault: vault))
    }
}
