//
//  CircleDashboardView.swift
//  VultisigApp
//
//  Created by Antigravity on 2025-12-11.
//

import SwiftUI

struct CircleDashboardView: View {
    let vault: Vault
    @ObservedObject var model: CircleViewModel
    
    @State private var showDeposit = false
    @State private var showWithdraw = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Balance Card
                balanceCard
                
                // Yield Info
                yieldCard
                
                // Actions
                HStack(spacing: 16) {
                    actionButton(title: NSLocalizedString("circleDashboardDeposit", comment: "Deposit"), icon: "arrow.down.left") {
                        showDeposit = true
                    }
                    actionButton(title: NSLocalizedString("circleDashboardWithdraw", comment: "Withdraw"), icon: "arrow.up.right") {
                        showWithdraw = true
                    }
                }
                .padding(.horizontal)
            }
            .padding(.top, 20)
        }
        .background(Theme.colors.bgPrimary)
        .refreshable {
            await loadData()
        }
        .onAppear {
            Task { await loadData() }
        }
        .sheet(isPresented: $showDeposit) {
            CircleDepositView(vault: vault)
        }
        .sheet(isPresented: $showWithdraw) {
            CircleWithdrawView(vault: vault, model: model)
        }
    }
    
    private var balanceCard: some View {
        VStack(spacing: 8) {
            Text(NSLocalizedString("circleDashboardTotalBalance", comment: "Total Balance"))
                .font(.body)
                .foregroundStyle(Theme.colors.textLight)
            
            Text("\(model.balance.description) USDC") // TODO: formatting with locale
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(Theme.colors.textPrimary)
            
            Text("≈ $1.00") // Placeholder for fiat
                .font(.caption)
                .foregroundStyle(Theme.colors.textExtraLight)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            LinearGradient.primaryGradient
                .opacity(0.1)
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(LinearGradient.primaryGradient, lineWidth: 1)
                )
        )
        .padding(.horizontal)
    }
    
    private var yieldCard: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("circleDashboardAPY", comment: "APY"))
                    .font(.caption)
                    .foregroundStyle(Theme.colors.textExtraLight)
                Text(model.apy)
                    .font(.title2)
                    .bold()
                    .foregroundStyle(Theme.colors.alertSuccess)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Divider()
                .frame(height: 40)
                .background(Theme.colors.textExtraLight)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("circleDashboardLifetimeEarnings", comment: "Lifetime Earnings"))
                    .font(.caption)
                    .foregroundStyle(Theme.colors.textExtraLight)
                Text("\(model.totalRewards) USDC")
                    .font(.title2)
                    .bold()
                    .foregroundStyle(Theme.colors.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 16)
        }
        .padding(16)
        .background(Theme.colors.primaryAccent1)
        .cornerRadius(16)
        .padding(.horizontal)
    }
    
    private func actionButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                Text(title)
                    .font(.body)
                    .bold()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.colors.primaryAccent1) // Keep as brand color or use primaryAccent with caution
            .cornerRadius(12)
            .foregroundStyle(Theme.colors.textPrimary)
        }
    }
    
    private func loadData() async {
        guard let address = vault.circleWalletAddress else { return }
        do {
            let (balance, yield) = try await model.logic.fetchData(address: address)
            await MainActor.run {
                model.balance = balance
                model.apy = yield.apy
                model.totalRewards = yield.totalRewards
            }
        } catch {
            print("Error fetching Circle data: \(error)")
        }
    }
}

// Localization keys to be added:
// "circleDashboardDeposit" = "Deposit";
// "circleDashboardWithdraw" = "Withdraw";
// "circleDashboardTotalBalance" = "Total Balance";
// "circleDashboardAPY" = "APY";
// "circleDashboardLifetimeEarnings" = "Lifetime Earnings";
