//
//  TronDashboardView.swift
//  VultisigApp
//
//  Created for TRON Freeze/Unfreeze integration
//

import SwiftUI

struct TronDashboardView: View {
    let vault: Vault
    @ObservedObject var model: TronViewModel
    let onRefresh: () async -> Void  // Callback for refresh
    @Environment(\.dismiss) var dismiss
    @Environment(\.router) var router

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

    /// Available balance in fiat (using TRX coin price)
    var availableBalanceFiat: String {
        guard let trxCoin = vault.nativeCoin(for: .tron) else {
            return "$0.00"
        }
        return TronViewLogic.formatFiat(balance: model.availableBalance, trxPrice: trxCoin.price)
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
            .clipShape(RoundedRectangle(cornerRadius: TronConstants.Design.cornerRadius))

            // Content
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("TRON")
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textSecondary)

                    if model.isLoadingBalance {
                        // Skeleton placeholder
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Theme.colors.bgSurface1)
                            .frame(width: 120, height: 24)
                            .shimmer()
                    } else {
                        Text(availableBalanceFiat)
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
        RoundedRectangle(cornerRadius: TronConstants.Design.cornerRadius)
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
                RoundedRectangle(cornerRadius: TronConstants.Design.cornerRadius)
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
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Theme.colors.bgSurface1)
                            .frame(width: 80, height: 20)
                            .shimmer()
                    } else {
                        Text(frozenBalanceFiat)
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
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.colors.bgSurface1)
                        .frame(width: 100, height: 20)
                        .shimmer()
                } else {
                    Text("\(model.totalFrozenBalance.formatted()) TRX")
                        .font(Theme.fonts.title2)
                        .foregroundStyle(Theme.colors.textPrimary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Action Buttons - Side by side
            HStack(spacing: 12) {
                DefiButton(
                    title: NSLocalizedString("tronUnfreezeButton", comment: "Unfreeze"),
                    icon: "minus",
                    type: .outline,
                    isSystemIcon: true,
                    action: { router.navigate(to: TronRoute.unfreeze(vault: vault, model: model)) }
                )
                .disabled(model.totalFrozenBalance <= 0)

                DefiButton(
                    title: NSLocalizedString("tronFreezeButton", comment: "Freeze"),
                    icon: "plus",
                    isSystemIcon: true,
                    action: { router.navigate(to: TronRoute.freeze(vault: vault)) }
                )
                .disabled(model.availableBalance <= 0)
            }
        }
        .padding(TronConstants.Design.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: TronConstants.Design.cornerRadius)
                .fill(Theme.colors.bgSurface1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: TronConstants.Design.cornerRadius)
                .stroke(Theme.colors.textSecondary.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Resources Card (Bandwidth & Energy)

    var resourcesCard: some View {
        HStack(spacing: 0) {
            // Bandwidth Section (Green)
            resourceSection(
                title: NSLocalizedString("tronBandwidth", comment: "Bandwidth"),
                icon: "gauge.with.needle",
                available: model.availableBandwidth,
                total: max(model.totalBandwidth, 1),  // Avoid division by zero
                accentColor: Theme.colors.alertSuccess,
                unit: "KB"
            )
            .padding(.leading, 16)
            .padding(.trailing, 12)

            // Vertical divider - touches top and bottom
            Rectangle()
                .fill(Theme.colors.textSecondary.opacity(0.3))
                .frame(width: 1)

            // Energy Section (Yellow/Orange)
            resourceSection(
                title: NSLocalizedString("tronEnergy", comment: "Energy"),
                icon: "bolt.fill",
                available: model.availableEnergy,
                total: max(model.totalEnergy, 1),  // Avoid division by zero
                accentColor: Theme.colors.alertWarning,
                unit: ""
            )
            .padding(.leading, 12)
            .padding(.trailing, 16)
        }
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: TronConstants.Design.cornerRadius)
                .fill(Theme.colors.bgSurface1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: TronConstants.Design.cornerRadius)
                .stroke(Theme.colors.textSecondary.opacity(0.2), lineWidth: 1)
        )
    }

    func resourceSection(title: String, icon: String, available: Int64, total: Int64, accentColor: Color, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title Label
            Text(title)
                .font(Theme.fonts.caption12)
                .foregroundStyle(accentColor)

            // Content row with icon and value
            HStack(spacing: 8) {
                // Icon with accent color background
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(accentColor.opacity(0.15))
                        .frame(width: 36, height: 36)

                    Image(systemName: icon)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(accentColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    // Value display
                    if model.isLoadingResources {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Theme.colors.bgSurface1)
                            .frame(width: 60, height: 14)
                            .shimmer()
                    } else {
                        Text(TronViewLogic.formatResourceValue(available: available, total: total, unit: unit))
                            .font(Theme.fonts.bodyMMedium)
                            .foregroundStyle(Theme.colors.textPrimary)
                    }

                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background track
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Theme.colors.bgPrimary)
                                .frame(height: 3)

                            if model.isLoadingResources {
                                // Shimmer loading state
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(accentColor.opacity(0.3))
                                    .frame(width: geometry.size.width * 0.5, height: 3)
                                    .shimmer()
                            } else {
                                // Progress fill
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(accentColor)
                                    .frame(width: geometry.size.width * progressValue(available: available, total: total), height: 3)
                            }
                        }
                    }
                    .frame(height: 3)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func progressValue(available: Int64, total: Int64) -> CGFloat {
        guard total > 0 else { return 0 }
        // Progress shows available percentage - full bar = all resources available
        return min(CGFloat(available) / CGFloat(total), 1.0)
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

                    Text("\(model.unfreezingBalance.formatted()) TRX")
                        .font(Theme.fonts.bodyLMedium)
                        .foregroundStyle(Theme.colors.textSecondary)
                }

                Divider()
                    .overlay(Theme.colors.textSecondary.opacity(0.3))

                ForEach(model.pendingWithdrawals) { withdrawal in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(withdrawal.amount.formatted()) TRX")
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
            }
            .padding(TronConstants.Design.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: TronConstants.Design.cornerRadius)
                    .fill(Theme.colors.bgSurface1)
            )
        }
    }
}

// MARK: - Shimmer Effect

private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.clear,
                        Theme.colors.textPrimary.opacity(0.4),
                        Color.clear
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase)
                .mask(content)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 200
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}
