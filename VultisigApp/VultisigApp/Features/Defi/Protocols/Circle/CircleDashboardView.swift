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
        content
    }
    
    // Internal access for extensions
    var balanceCard: some View {
        VStack(spacing: 8) {
            Text(LocalizedStringKey("circleDashboardTotalBalance"))
                .font(.body)
                .foregroundStyle(Theme.colors.textLight)
            
            Text("\(model.balance.formatted()) USDC")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(Theme.colors.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(cardBackground)
        .padding(.horizontal)
    }
    
    var yieldCard: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey("circleDashboardAPY"))
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
                Text(LocalizedStringKey("circleDashboardLifetimeEarnings"))
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
        .background(cardBackground)
        .padding(.horizontal)
    }
    
    // Internal access for extensions
    var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .inset(by: 0.5)
            .stroke(Color(hex: "34E6BF").opacity(0.17))
            .fill(
                LinearGradient(
                    stops: [
                        Gradient.Stop(color: Color(hex: "34E6BF"), location: 0.00),
                        Gradient.Stop(color: Color(red: 0.11, green: 0.5, blue: 0.42).opacity(0), location: 1.00),
                    ],
                    startPoint: UnitPoint(x: 0.5, y: 0),
                    endPoint: UnitPoint(x: 0.5, y: 1)
                ).opacity(0.09)
            )
    }
    

    // Internal access for extensions
    func loadData() async {
        guard let address = vault.circleWalletAddress else { return }
        do {
            let (balance, yield) = try await model.logic.fetchData(address: address, vault: vault)
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

#if os(iOS)
extension CircleDashboardView {
    var content: some View {
        ZStack {
            VaultMainScreenBackground()
            
            ScrollView {
                VStack(spacing: 20) {
                    balanceCard
                    yieldCard
                    
                    HStack(spacing: 16) {
                        DefiButton(
                            title: NSLocalizedString("circleDashboardDeposit", comment: "Deposit"),
                            icon: "arrow.down.left",
                            action: { showDeposit = true }
                        )
                        
                        DefiButton(
                            title: NSLocalizedString("circleDashboardWithdraw", comment: "Withdraw"),
                            icon: "arrow.up.right",
                            action: { showWithdraw = true }
                        )
                    }
                    .padding(.horizontal)
                }
                .padding(.top, 20)
            }
            .refreshable {
                await loadData()
            }
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
        .navigationTitle(NSLocalizedString("circleTitle", comment: "Circle"))
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationBackButton()
            }
        }
    }
}
#endif

#if os(macOS)
extension CircleDashboardView {
    var content: some View {
        ZStack {
            VaultMainScreenBackground()
            
            ScrollView {
                VStack(spacing: 20) {
                    balanceCard
                    yieldCard
                    
                    HStack(spacing: 16) {
                        DefiButton(
                            title: NSLocalizedString("circleDashboardDeposit", comment: "Deposit"),
                            icon: "arrow.down.left",
                            action: { showDeposit = true }
                        )
                        
                        DefiButton(
                            title: NSLocalizedString("circleDashboardWithdraw", comment: "Withdraw"),
                            icon: "arrow.up.right",
                            action: { showWithdraw = true }
                        )
                    }
                    .padding(.horizontal)
                }
                .padding(.top, 20)
            }
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
        .navigationTitle(NSLocalizedString("circleTitle", comment: "Circle"))
        .toolbar {
             ToolbarItem(placement: .navigation) {
                 NavigationBackButton()
             }
        }
    }
}
#endif

// Localization keys to be added:
// "circleDashboardDeposit" = "Deposit";
// "circleDashboardWithdraw" = "Withdraw";
// "circleDashboardTotalBalance" = "Total Balance";
// "circleDashboardAPY" = "APY";
// "circleDashboardLifetimeEarnings" = "Lifetime Earnings";
