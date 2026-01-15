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
    
    func loadData() async {
        guard let trxCoin = TronViewLogic.getTrxCoin(vault: vault) else { return }
        
        await BalanceService.shared.updateBalance(for: trxCoin)
        
        do {
            let (available, frozenBandwidth, frozenEnergy, unfreezing, resource) = try await model.logic.fetchData(vault: vault)
            await MainActor.run {
                model.availableBalance = available
                model.frozenBandwidthBalance = frozenBandwidth
                model.frozenEnergyBalance = frozenEnergy
                model.unfreezingBalance = unfreezing
                
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
