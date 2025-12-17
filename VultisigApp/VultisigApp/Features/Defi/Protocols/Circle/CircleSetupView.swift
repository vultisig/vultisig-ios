//
//  CircleSetupView.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2025-12-11.
//

import SwiftUI

struct CircleSetupView: View {
    let vault: Vault
    @ObservedObject var model: CircleViewModel
    
    @State var showInfoBanner = true
    
    var walletUSDCBalance: Decimal {
        let isSepolia = vault.coins.contains { $0.chain == .ethereumSepolia }
        let chain: Chain = isSepolia ? .ethereumSepolia : .ethereum
        if let usdcCoin = vault.coins.first(where: { $0.chain == chain && $0.ticker == "USDC" }) {
            return usdcCoin.balanceDecimal
        }
        return .zero
    }
    
    var body: some View {
        ZStack {
            VaultMainScreenBackground()
            
            ScrollView {
                VStack(spacing: 24) {
                    topBanner
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(NSLocalizedString("circleSetupDeposited", comment: "Deposited"))
                            .font(.headline)
                            .foregroundStyle(Theme.colors.textPrimary)
                        
                        Text(NSLocalizedString("circleSetupDepositDescription", comment: "Deposit your $USDC..."))
                            .font(.body)
                            .foregroundStyle(Theme.colors.textLight)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    
                    if showInfoBanner {
                        InfoBannerView(
                            description: NSLocalizedString("circleSetupInfoText", comment: "Funds remain..."),
                            type: .info,
                            leadingIcon: "info.circle",
                            onClose: {
                                withAnimation { showInfoBanner = false }
                            }
                        )
                        .padding(.horizontal, 16)
                    }
                    
                    bottomCard
                }
                .padding(.vertical, 20)
            }
        }
        .navigationTitle("")
        .toolbar {
            toolbarContent
        }
    }
    
    var topBanner: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("circleSetupAccountTitle", comment: "Circle USDC Account"))
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
        .padding(.horizontal, 16)
    }
    
    var bottomCard: some View {
        VStack(spacing: 24) {
            HStack(spacing: 12) {
                Image("usdc")
                    .resizable()
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("circleSetupUSDCDeposited", comment: "USDC deposited"))
                        .font(.caption)
                        .foregroundStyle(Theme.colors.textLight)
                    
                    Text("\(model.balance.formatted()) USDC")
                        .font(.title2)
                        .bold()
                        .foregroundStyle(Theme.colors.textPrimary)
                }
                Spacer()
            }
            
            DefiButton(
                title: NSLocalizedString("circleSetupOpenAccount", comment: "Open Account"),
                icon: "arrow.right",
                action: {
                    Task { await createWallet() }
                }
            )
        }
        .padding(24)
        .background(cardBackground)
        .padding(.horizontal, 16)
    }
    
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
    
    func createWallet() async {
        await MainActor.run { model.isLoading = true }
        do {
            let newAddress = try await model.logic.createWallet(vault: vault)
            await MainActor.run {
                vault.circleWalletAddress = newAddress
                model.isLoading = false
            }
        } catch {
            await MainActor.run {
                model.error = error
                model.isLoading = false
            }
        }
    }
}
