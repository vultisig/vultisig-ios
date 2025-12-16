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
            
            // Buttons moved to usdcDepositedCard
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

    

    // Internal access for extensions
    func loadData() async {
        guard let mscaAddress = vault.circleWalletAddress else { return }
        
        // Refresh Vault Balances (USDC and ETH) to ensure "Wallet Balance" is up to date
        let isSepolia = vault.coins.contains { $0.chain == .ethereumSepolia }
        let chain: Chain = isSepolia ? .ethereumSepolia : .ethereum
        
        let coinsToRefresh = vault.coins.filter { coin in
            coin.chain == chain && (coin.ticker == "USDC" || coin.isNativeToken)
        }
        
        for coin in coinsToRefresh {
            await BalanceService.shared.updateBalance(for: coin)
        }
        
        // Run MSCA verification
        await verifyMSCAOnLoad(mscaAddress: mscaAddress, chain: chain)
        
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
            print("Error fetching Circle data: \(error)")
        }
    }
    
    // DEBUG: Verify MSCA on dashboard load
    private func verifyMSCAOnLoad(mscaAddress: String, chain: Chain) async {
        let vaultEthAddress = vault.coins.first(where: { $0.chain == chain })?.address ?? ""
        
        print("")
        print("╔══════════════════════════════════════════════════════════════════╗")
        print("║           CIRCLE DASHBOARD - MSCA VERIFICATION                   ║")
        print("╠══════════════════════════════════════════════════════════════════╣")
        print("║ Timestamp: \(Date())")
        print("║ Chain: \(chain.name)")
        print("╠══════════════════════════════════════════════════════════════════╣")
        print("║ ADDRESSES:")
        print("║   Vault ETH Address: \(vaultEthAddress)")
        print("║   Circle MSCA:       \(mscaAddress)")
        print("╠══════════════════════════════════════════════════════════════════╣")
        
        do {
            let service = try EvmService.getService(forChain: chain)
            
            // 1. Check deployment
            print("║ DEPLOYMENT STATUS:")
            let code = try await service.getCode(address: mscaAddress)
            let isDeployed = code != "0x" && code.count > 2
            print("║   Contract code length: \(code.count) chars")
            print("║   Is Deployed: \(isDeployed ? "✅ YES" : "❌ NO - NOT DEPLOYED!")")
            
            if !isDeployed {
                print("║")
                print("║ ⚠️  WARNING: MSCA is NOT deployed on-chain!")
                print("║ The backend needs to call transferNativeOwnership to deploy.")
                print("╚══════════════════════════════════════════════════════════════════╝")
                print("")
                return
            }
            
            // 2. Fetch owner
            print("║")
            print("║ OWNERSHIP:")
            let owner = await service.fetchContractOwner(contractAddress: mscaAddress)
            if let owner = owner {
                print("║   Owner from contract: \(owner)")
                let ownerMatch = owner.lowercased() == vaultEthAddress.lowercased()
                print("║   Matches vault address: \(ownerMatch ? "✅ YES" : "❌ NO - MISMATCH!")")
                
                if !ownerMatch {
                    print("║")
                    print("║ ❌ OWNER MISMATCH!")
                    print("║   Expected (vault): \(vaultEthAddress)")
                    print("║   Actual (MSCA):    \(owner)")
                    print("║   Withdrawals will FAIL with this mismatch!")
                }
            } else {
                print("║   Owner: ❓ Could not fetch (may not implement owner())")
                print("║   Check Etherscan manually for ownership info")
            }
            
            // 3. Balances
            print("║")
            print("║ BALANCES:")
            
            let usdcContract = chain == .ethereumSepolia 
                ? "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238"
                : "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
            
            let usdcBalance = try await service.fetchERC20TokenBalance(contractAddress: usdcContract, walletAddress: mscaAddress)
            let usdcFormatted = Decimal(string: String(usdcBalance))! / pow(10, 6)
            print("║   MSCA USDC: \(usdcFormatted) USDC")
            
            if let nativeCoin = vault.coins.first(where: { $0.chain == chain && $0.isNativeToken }) {
                let ethBalanceStr = try await service.getBalance(coin: nativeCoin.toCoinMeta(), address: mscaAddress)
                let ethBalanceWei = Decimal(string: ethBalanceStr) ?? 0
                let ethBalance = ethBalanceWei / pow(10, 18)
                print("║   MSCA ETH:  \(ethBalance) ETH")
                
                // Vault balances
                let vaultEthStr = try await service.getBalance(coin: nativeCoin.toCoinMeta(), address: vaultEthAddress)
                let vaultEthWei = Decimal(string: vaultEthStr) ?? 0
                let vaultEth = vaultEthWei / pow(10, 18)
                print("║   Vault ETH: \(vaultEth) ETH (for gas)")
            }
            
            print("╠══════════════════════════════════════════════════════════════════╣")
            print("║ LINKS:")
            print("║   MSCA:  https://etherscan.io/address/\(mscaAddress)")
            print("║   Vault: https://etherscan.io/address/\(vaultEthAddress)")
            print("╚══════════════════════════════════════════════════════════════════╝")
            print("")
            
        } catch {
            print("║ ❌ Verification error: \(error)")
            print("╚══════════════════════════════════════════════════════════════════╝")
            print("")
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
                    // ETH Card Removed
                    
                    // Only show yield details if real API data is available
                    if !model.apy.isEmpty {
                        yieldDetailsCard
                    }
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
                    // ETH Card Removed
                    
                    // Only show yield details if real API data is available
                    if !model.apy.isEmpty {
                        yieldDetailsCard
                    }
                }
                .padding(.vertical, 20)
            }
        }
        .onAppear {
            Task { await loadData() }
        }
        .sheet(isPresented: $showDeposit) {
            CircleDepositView(vault: vault)
                .presentationSizingFitted()
                .applySheetSize(700, nil)
                .background(Theme.colors.bgPrimary)
        }
        .sheet(isPresented: $showWithdraw) {
            CircleWithdrawView(vault: vault, model: model)
                .presentationSizingFitted()
                .applySheetSize(700, nil)
                .background(Theme.colors.bgPrimary)
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
