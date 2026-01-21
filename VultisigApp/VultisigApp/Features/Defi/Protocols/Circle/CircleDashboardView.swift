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
    @Environment(\.dismiss) var dismiss
    @Environment(\.router) var router

    @AppStorage("appClosedBanners") var appClosedBanners: [String] = []

    let circleDashboardBannerId = "circleDashboardInfoBanner"

    var showInfoBanner: Bool {
        !appClosedBanners.contains(circleDashboardBannerId)
    }

    var walletUSDCBalance: Decimal {
        return CircleViewLogic.getWalletUSDCBalance(vault: vault)
    }

    var body: some View {
        content
    }

    var topBanner: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("circleSetupAccountTitle", comment: "Circle USDC Account"))
                    .font(CircleConstants.Fonts.title)
                    .foregroundStyle(Theme.colors.textSecondary)

                Text("$\(walletUSDCBalance.formatted())")
                    .font(CircleConstants.Fonts.balance)
                    .foregroundStyle(Theme.colors.textPrimary)
            }
            Spacer()
            Image("circle-logo")
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
        .padding(CircleConstants.Design.cardPadding)
        .background(cardBackground)
    }

    var cardBackground: some View {
        RoundedRectangle(cornerRadius: CircleConstants.Design.cornerRadius)
            .inset(by: 0.5)
            .stroke(Color(hex: "34E6BF").opacity(0.17))
            .fill(
                LinearGradient(
                    stops: [
                        Gradient.Stop(color: Color(hex: "34E6BF"), location: 0.00),
                        Gradient.Stop(color: Color(red: 0.11, green: 0.5, blue: 0.42).opacity(0), location: 1.00)
                    ],
                    startPoint: UnitPoint(x: 0.5, y: 0),
                    endPoint: UnitPoint(x: 0.5, y: 1)
                ).opacity(0.09)
            )
    }

    var usdcDepositedCard: some View {
        VStack(spacing: 24) {
            HStack(spacing: 12) {
                Image("usdc")
                    .resizable()
                    .frame(width: 39, height: 39)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("circleDashboardUSDCDeposited", comment: "USDC deposited"))
                        .font(CircleConstants.Fonts.subtitle)
                        .foregroundStyle(Theme.colors.textSecondary)

                    Text("\(model.balance.formatted()) USDC")
                        .font(Theme.fonts.priceBodyL)
                        .foregroundStyle(Theme.colors.textPrimary)

                    Text("$\(model.balance.formatted())")
                        .font(CircleConstants.Fonts.subtitle)
                        .foregroundStyle(Theme.colors.textSecondary)
                }
                Spacer()
            }

            VStack {
                DefiButton(
                    title: NSLocalizedString("circleDashboardWithdraw", comment: "Withdraw"),
                    icon: "arrow.down",
                    type: .outline,
                    isSystemIcon: true,
                    action: { router.navigate(to: CircleRoute.withdraw(vault: vault, model: model)) }
                )
                .disabled(model.balance <= 0)

                DefiButton(
                    title: NSLocalizedString("circleDashboardDepositUSDC", comment: "Deposit"),
                    icon: "arrow.up",
                    isSystemIcon: true,
                    action: { router.navigate(to: CircleRoute.deposit(vault: vault)) }
                )
            }
        }
        .padding(CircleConstants.Design.cardPadding)
        .background(cardBackground)
    }

    func loadData() async {
        guard let mscaAddress = vault.circleWalletAddress else { return }

        let (chain, _) = CircleViewLogic.getChainDetails(vault: vault)

        let coinsToRefresh = vault.coins.filter { coin in
            coin.chain == chain && (coin.ticker == "USDC" || coin.isNativeToken)
        }

        for coin in coinsToRefresh {
            await BalanceService.shared.updateBalance(for: coin)
        }

        do {
            let (balance, ethBalance) = try await model.logic.fetchData(address: mscaAddress, vault: vault)
            await MainActor.run {
                model.balance = balance
                model.ethBalance = ethBalance
            }
        } catch {
            print("Error loading Circle data: \(error.localizedDescription)")
            await MainActor.run {
                model.error = error
            }
        }
    }
}
