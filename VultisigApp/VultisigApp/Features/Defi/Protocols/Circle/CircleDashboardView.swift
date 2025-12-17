//
//  CircleDashboardView.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2025-12-11.
//

import SwiftUI

struct CircleDashboardView: View {
    let vault: Vault
    @ObservedObject var model: CircleViewModel
    
    @State var showInfoBanner = true
    @State var showDeposit = false
    @State var showWithdraw = false
    
    var walletUSDCBalance: Decimal {
        let isSepolia = vault.coins.contains { $0.chain == .ethereumSepolia }
        let chain: Chain = isSepolia ? .ethereumSepolia : .ethereum
        if let usdcCoin = vault.coins.first(where: { $0.chain == chain && $0.ticker == "USDC" }) {
            return usdcCoin.balanceDecimal
        }
        return .zero
    }
    
    var body: some View {
        content
    }
    
    var topBanner: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("circleDashboardCircleUSDCAccount", comment: "Circle USDC Account"))
                    .font(.subheadline)
                    .bold()
                    .foregroundStyle(Theme.colors.textLight)
                
                Text("$\(walletUSDCBalance.formatted())") 
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Theme.colors.textPrimary)
            }
            Spacer()
            Image(systemName: "circle.hexagongrid")
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
        .padding(24)
        .background(cardBackground)
        .padding(.horizontal)
    }
    
    var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Theme.colors.bgSecondary)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Theme.colors.borderLight, lineWidth: 1)
            )
    }
    
    var usdcDepositedCard: some View {
        VStack(spacing: 24) {
             HStack(spacing: 12) {
                Image("usdc")
                    .resizable()
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("circleDashboardUSDCDeposited", comment: "USDC deposited"))
                        .font(.caption)
                        .foregroundStyle(Theme.colors.textLight)
                    
                    Text("\(model.balance.formatted()) USDC")
                        .font(.title2)
                        .bold()
                        .foregroundStyle(Theme.colors.textPrimary)
                    
                    Text("$\(model.balance.formatted())")
                        .font(.caption)
                        .foregroundStyle(Theme.colors.textLight)
                }
                Spacer()
            }
            
            HStack(spacing: 12) {
                DefiButton(
                    title: NSLocalizedString("circleDashboardWithdraw", comment: "Withdraw"),
                    icon: "arrow.up.right",
                    action: { showWithdraw = true }
                )
                .disabled(model.balance <= 0)
                
                DefiButton(
                    title: NSLocalizedString("circleDashboardDepositUSDC", comment: "Deposit"),
                    icon: "arrow.down.left",
                    action: { showDeposit = true }
                )
            }
            
            if model.ethBalance <= 0 && model.balance > 0 {
                Text(NSLocalizedString("circleDashboardETHRequired", comment: "ETH is required..."))
                    .font(.caption)
                    .foregroundStyle(Theme.colors.alertWarning)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24)
        .background(cardBackground)
        .padding(.horizontal)
    }
    
    var yieldDetailsCard: some View {
        VStack(spacing: 24) {
            HStack {
                Text(NSLocalizedString("circleDashboardYieldDetails", comment: "Circle Yield Details"))
                    .font(.headline)
                    .foregroundStyle(Theme.colors.textPrimary)
                Spacer()
            }
            
            VStack(spacing: 12) {
                detailRow(title: "APY", value: model.apy)
                detailRow(title: NSLocalizedString("circleDashboardTotalRewards", comment: "Total Rewards"), value: "\(model.totalRewards) USDC")
                detailRow(title: NSLocalizedString("circleDashboardCurrentRewards", comment: "Current Rewards"), value: "+\(model.currentRewards) USDC")
            }
        }
        .padding(24)
        .background(cardBackground)
        .padding(.horizontal)
    }
    
    func detailRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Theme.colors.textLight)
            Spacer()
            Text(value)
                .font(.subheadline)
                .bold()
                .foregroundStyle(Theme.colors.textPrimary)
        }
    }

    func loadData() async {
        guard let mscaAddress = vault.circleWalletAddress else { return }
        
        let isSepolia = vault.coins.contains { $0.chain == .ethereumSepolia }
        let chain: Chain = isSepolia ? .ethereumSepolia : .ethereum
        
        let coinsToRefresh = vault.coins.filter { coin in
            coin.chain == chain && (coin.ticker == "USDC" || coin.isNativeToken)
        }
        
        for coin in coinsToRefresh {
            await BalanceService.shared.updateBalance(for: coin)
        }
        
        do {
            let (balance, ethBalance, yield) = try await model.logic.fetchData(address: mscaAddress, vault: vault)
            await MainActor.run {
                model.balance = balance
                model.ethBalance = ethBalance
                model.apy = yield.apy
                model.totalRewards = yield.totalRewards
                model.currentRewards = yield.currentRewards
            }
        } catch {
            // Log error silently or use proper logger
        }
    }
}
