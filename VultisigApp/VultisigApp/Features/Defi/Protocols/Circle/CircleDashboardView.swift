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
    
    @State private var showInfoBanner = true
    @State private var showDeposit = false
    @State private var showWithdraw = false
    
    /// Wallet USDC balance (from vault coins - what user HAS available)
    private var walletUSDCBalance: Decimal {
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
    
    // Internal access for extensions
    var topBanner: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("circleDashboardCircleUSDCAccount", comment: "Circle USDC Account"))
                    .font(.subheadline)
                    .bold()
                    .foregroundStyle(Theme.colors.textLight)
                
                // Wallet USDC balance (what user HAS on blockchain)
                Text("$\(walletUSDCBalance.formatted())") 
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Theme.colors.textPrimary)
            }
            Spacer()
            // Decorative graphic
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
    
    var usdcDepositedCard: some View {
        VStack(spacing: 24) {
             HStack(spacing: 12) {
                Image("usdc") // Existing USDC asset
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
                    
                    Text("$\(model.balance.formatted())") // Fiat
                        .font(.caption)
                        .foregroundStyle(Theme.colors.textLight)
                }
                Spacer()
            }
            
            DefiButton(
                title: NSLocalizedString("circleDashboardDepositUSDC", comment: "Deposit USDC"),
                icon: "arrow.down.left",
                action: { showDeposit = true }
            )
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
            
            VStack(spacing: 12) {
                DefiButton(
                    title: NSLocalizedString("circleDashboardWithdraw", comment: "Withdraw"),
                    icon: "arrow.up.right",
                    action: { showWithdraw = true }
                )
                .disabled(model.ethBalance <= 0)
                
                if model.ethBalance <= 0 {
                    Text(NSLocalizedString("circleDashboardETHRequired", comment: "ETH is required..."))
                        .font(.caption)
                        .foregroundStyle(Theme.colors.alertWarning)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(24)
        .background(cardBackground)
        .padding(.horizontal)
    }
    
    private func detailRow(title: String, value: String) -> some View {
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
            let (balance, ethBalance, yield) = try await model.logic.fetchData(address: address, vault: vault)
            await MainActor.run {
                model.balance = balance
                model.ethBalance = ethBalance
                model.apy = yield.apy
                model.totalRewards = yield.totalRewards
                model.currentRewards = yield.currentRewards
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
                VStack(spacing: 24) {
                    topBanner
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(NSLocalizedString("circleDashboardDeposited", comment: "Deposited"))
                            .font(.headline)
                            .foregroundStyle(Theme.colors.textPrimary)
                        
                        Text(NSLocalizedString("circleDashboardDepositDescription", comment: "Deposit your $USDC..."))
                            .font(.body)
                            .foregroundStyle(Theme.colors.textLight)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    
                    if showInfoBanner {
                         InfoBannerView(
                            description: NSLocalizedString("circleDashboardInfoText", comment: "Funds remain..."),
                            type: .info,
                            leadingIcon: "info.circle",
                            onClose: {
                                withAnimation { showInfoBanner = false }
                            }
                        )
                        .padding(.horizontal, 16)
                    }
                    
                    usdcDepositedCard
                    yieldDetailsCard
                }
                .padding(.vertical, 20)
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
                VStack(spacing: 24) {
                    topBanner
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(NSLocalizedString("circleDashboardDeposited", comment: "Deposited"))
                            .font(.headline)
                            .foregroundStyle(Theme.colors.textPrimary)
                        
                        Text(NSLocalizedString("circleDashboardDepositDescription", comment: "Deposit your $USDC..."))
                            .font(.body)
                            .foregroundStyle(Theme.colors.textLight)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    
                    if showInfoBanner {
                         InfoBannerView(
                            description: NSLocalizedString("circleDashboardInfoText", comment: "Funds remain..."),
                            type: .info,
                            leadingIcon: "info.circle",
                            onClose: {
                                withAnimation { showInfoBanner = false }
                            }
                        )
                        .padding(.horizontal, 16)
                    }
                    
                    usdcDepositedCard
                    yieldDetailsCard
                }
                .padding(.vertical, 20)
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
