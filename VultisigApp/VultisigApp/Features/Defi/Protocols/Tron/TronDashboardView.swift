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
    
    /// Frozen balance in fiat (using TRX coin price)
    var frozenBalanceFiat: String {
        guard let trxCoin = vault.coins.first(where: { $0.chain == .tron && $0.isNativeToken }) else {
            return "$0.00"
        }
        let fiatValue = model.totalFrozenBalance * Decimal(trxCoin.price)
        return fiatValue.formatToFiat(includeCurrencySymbol: true)
    }
    
    var body: some View {
        content
    }
    
    var topBanner: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text("TRON")
                    .font(TronConstants.Fonts.title)
                    .foregroundStyle(Theme.colors.textSecondary)
                
                Text("\(model.availableBalance.formatted()) TRX")
                    .font(TronConstants.Fonts.balance)
                    .foregroundStyle(Theme.colors.textPrimary)
            }
            Spacer()
            Image("tron")
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)
                .clipShape(Circle())
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
                    
                    Text(frozenBalanceFiat)
                        .font(Theme.fonts.title2)
                        .foregroundStyle(Theme.colors.textPrimary)
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
                
                Text("\(model.totalFrozenBalance.formatted()) TRX")
                    .font(Theme.fonts.title2)
                    .foregroundStyle(Theme.colors.textPrimary)
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
            }
        }
        .padding(TronConstants.Design.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: TronConstants.Design.cornerRadius)
                .fill(Theme.colors.bgSurface1)
        )
    }
    
    // MARK: - Resources Card (Bandwidth & Energy)
    
    var resourcesCard: some View {
        HStack(spacing: 12) {
            // Bandwidth Section (Green)
            resourceSection(
                title: NSLocalizedString("tronBandwidth", comment: "Bandwidth"),
                icon: "arrow.up.arrow.down",
                available: model.availableBandwidth,
                total: max(model.totalBandwidth, 1),  // Avoid division by zero
                accentColor: Theme.colors.alertSuccess
            )
            
            // Energy Section (Yellow/Orange)
            resourceSection(
                title: NSLocalizedString("tronEnergy", comment: "Energy"),
                icon: "bolt.fill",
                available: model.availableEnergy,
                total: max(model.totalEnergy, 1),  // Avoid division by zero
                accentColor: Theme.colors.alertWarning
            )
        }
        .padding(TronConstants.Design.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: TronConstants.Design.cornerRadius)
                .fill(Theme.colors.bgSurface1)
        )
    }
    
    func resourceSection(title: String, icon: String, available: Int64, total: Int64, accentColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title Label
            Text(title)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textSecondary)
            
            // Content box with accent color
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    // Icon
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundStyle(accentColor)
                        .frame(width: 24, height: 24)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        // Value display
                        Text(formatResourceValue(available: available, total: total))
                            .font(Theme.fonts.bodyMMedium)
                            .foregroundStyle(Theme.colors.textPrimary)
                        
                        // Progress bar
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                // Background track
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Theme.colors.bgSurface1)
                                    .frame(height: 4)
                                
                                // Progress fill
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(accentColor)
                                    .frame(width: geometry.size.width * progressValue(available: available, total: total), height: 4)
                            }
                        }
                        .frame(height: 4)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(accentColor.opacity(0.1))
            )
        }
        .frame(maxWidth: .infinity)
    }
    
    func formatResourceValue(available: Int64, total: Int64) -> String {
        // Format as KB for bandwidth if large enough
        if total >= 1000 {
            let availableKB = Double(available) / 1000.0
            let totalKB = Double(total) / 1000.0
            return String(format: "%.2f/%.2fKB", availableKB, totalKB)
        }
        return "\(available)/\(total)"
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
