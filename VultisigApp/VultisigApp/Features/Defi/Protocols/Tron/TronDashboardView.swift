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
    @Environment(\.dismiss) var dismiss
    @Environment(\.router) var router

    @AppStorage("appClosedBanners") var appClosedBanners: [String] = []
    
    let tronDashboardBannerId = "tronDashboardInfoBanner"
    
    var showInfoBanner: Bool {
        !appClosedBanners.contains(tronDashboardBannerId)
    }
    
    var walletTrxBalance: Decimal {
        return TronViewLogic.getWalletTrxBalance(vault: vault)
    }
    
    var body: some View {
        content
    }
    
    var topBanner: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("tronDashboardTitle", comment: "TRON Staking"))
                    .font(TronConstants.Fonts.title)
                    .foregroundStyle(Theme.colors.textSecondary)
                
                Text("\(model.availableBalance.formatted()) TRX")
                    .font(TronConstants.Fonts.balance)
                    .foregroundStyle(Theme.colors.textPrimary)
            }
            Spacer()
            Image("tron-logo")
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Theme.colors.primaryAccent1, Theme.colors.primaryAccent4],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .padding(TronConstants.Design.cardPadding)
        .background(cardBackground)
    }
    
    
    var cardBackground: some View {
        RoundedRectangle(cornerRadius: TronConstants.Design.cornerRadius)
            .inset(by: 0.5)
            .stroke(Color(hex: "FF0013").opacity(0.17))
            .fill(
                LinearGradient(
                    stops: [
                        Gradient.Stop(color: Color(hex: "FF0013"), location: 0.00),
                        Gradient.Stop(color: Color(red: 0.5, green: 0.11, blue: 0.11).opacity(0), location: 1.00),
                    ],
                    startPoint: UnitPoint(x: 0.5, y: 0),
                    endPoint: UnitPoint(x: 0.5, y: 1)
                ).opacity(0.09)
            )
    }
    
    var frozenBalanceCard: some View {
        VStack(spacing: 24) {
            HStack(spacing: 12) {
                Image("tron-logo")
                    .resizable()
                    .frame(width: 39, height: 39)
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("tronFrozenBalance", comment: "Frozen TRX"))
                        .font(TronConstants.Fonts.subtitle)
                        .foregroundStyle(Theme.colors.textSecondary)
                    
                    Text("\(model.totalFrozenBalance.formatted()) TRX")
                        .font(Theme.fonts.priceBodyL)
                        .foregroundStyle(Theme.colors.textPrimary)
                }
                Spacer()
            }
            
            // Resource info
            VStack(spacing: 8) {
                resourceRow(
                    title: NSLocalizedString("tronBandwidth", comment: "Bandwidth"),
                    available: model.availableBandwidth,
                    total: model.totalBandwidth
                )
                
                resourceRow(
                    title: NSLocalizedString("tronEnergy", comment: "Energy"),
                    available: model.availableEnergy,
                    total: model.totalEnergy
                )
            }
            
            VStack {
                DefiButton(
                    title: NSLocalizedString("tronUnfreezeButton", comment: "Unfreeze"),
                    icon: "arrow.down",
                    type: .outline,
                    isSystemIcon: true,
                    action: { router.navigate(to: TronRoute.unfreeze(vault: vault, model: model)) }
                )
                .disabled(model.totalFrozenBalance <= 0)

                DefiButton(
                    title: NSLocalizedString("tronFreezeButton", comment: "Freeze"),
                    icon: "arrow.up",
                    isSystemIcon: true,
                    action: { router.navigate(to: TronRoute.freeze(vault: vault)) }
                )
            }
        }
        .padding(TronConstants.Design.cardPadding)
        .background(cardBackground)
    }
    
    func resourceRow(title: String, available: Int64, total: Int64) -> some View {
        HStack {
            Text(title)
                .font(TronConstants.Fonts.subtitle)
                .foregroundStyle(Theme.colors.textSecondary)
            
            Spacer()
            
            Text("\(available) / \(total)")
                .font(TronConstants.Fonts.subtitle)
                .foregroundStyle(Theme.colors.textPrimary)
        }
    }
    
    @ViewBuilder
    var pendingWithdrawalsCard: some View {
        if model.hasPendingWithdrawals {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(Theme.colors.alertWarning)
                    
                    Text(NSLocalizedString("tronPendingWithdrawals", comment: "Pending Withdrawals"))
                        .font(Theme.fonts.bodyLMedium)
                        .foregroundStyle(Theme.colors.textPrimary)
                    
                    Spacer()
                    
                    Text("\(model.unfreezingBalance.formatted()) TRX")
                        .font(Theme.fonts.bodyLMedium)
                        .foregroundStyle(Theme.colors.alertWarning)
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
                                    .foregroundStyle(Theme.colors.alertSuccess)
                            } else {
                                Text(withdrawalTimeRemaining(withdrawal.expirationDate))
                                    .font(Theme.fonts.caption12)
                                    .foregroundStyle(Theme.colors.textSecondary)
                            }
                        }
                        
                        Spacer()
                        
                        if withdrawal.isClaimable {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Theme.colors.alertSuccess)
                        } else {
                            Image(systemName: "hourglass")
                                .foregroundStyle(Theme.colors.alertWarning)
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
    
    func withdrawalTimeRemaining(_ date: Date) -> String {
        let now = Date()
        let remaining = date.timeIntervalSince(now)
        
        if remaining <= 0 {
            return NSLocalizedString("tronReadyToClaim", comment: "Ready to claim")
        }
        
        let days = Int(remaining / 86400)
        let hours = Int((remaining.truncatingRemainder(dividingBy: 86400)) / 3600)
        
        if days > 0 {
            return String(format: NSLocalizedString("tronTimeRemainingDays", comment: "%d days, %d hours"), days, hours)
        } else {
            let minutes = Int((remaining.truncatingRemainder(dividingBy: 3600)) / 60)
            return String(format: NSLocalizedString("tronTimeRemainingHours", comment: "%d hours, %d minutes"), hours, minutes)
        }
    }
    
    func loadData() async {
        guard let trxCoin = TronViewLogic.getTrxCoin(vault: vault) else { return }
        
        await BalanceService.shared.updateBalance(for: trxCoin)
        
        do {
            let (available, frozenBandwidth, frozenEnergy, unfreezing, pendingWithdrawals, resource) = try await model.logic.fetchData(vault: vault)
            await MainActor.run {
                model.availableBalance = available
                model.frozenBandwidthBalance = frozenBandwidth
                model.frozenEnergyBalance = frozenEnergy
                model.unfreezingBalance = unfreezing
                model.pendingWithdrawals = pendingWithdrawals
                
                if let resource = resource {
                    model.availableBandwidth = resource.calculateAvailableBandwidth()
                    model.totalBandwidth = resource.freeNetLimit + resource.NetLimit
                    model.availableEnergy = resource.EnergyLimit - resource.EnergyUsed
                    model.totalEnergy = resource.EnergyLimit
                }
            }
        } catch {
            print("Error loading TRON data: \(error.localizedDescription)")
            await MainActor.run {
                model.error = error
            }
        }
    }
}
