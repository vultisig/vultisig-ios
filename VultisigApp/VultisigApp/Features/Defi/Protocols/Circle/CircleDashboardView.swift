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

    var body: some View {
        content
    }

    var content: some View {
        VStack(spacing: 0) {
            scrollViewContent
        }
        .frame(maxHeight: .infinity)
        .onAppear {
            Task { await loadData() }
        }
    }

    var scrollViewContent: some View {
        ScrollView {
            dashboardContent
        }
        #if os(iOS)
        .refreshable {
            await loadData()
        }
        #endif
    }

    var dashboardContent: some View {
        VStack(spacing: CircleConstants.Design.verticalSpacing) {
            topBanner

            headerDescription

            InfoBannerView(
                description: NSLocalizedString("circleDashboardInfoText", comment: "Funds remain..."),
                type: .info,
                leadingIcon: nil,
                onClose: {
                    withAnimation { appClosedBanners.append(circleDashboardBannerId) }
                }
            )
            .showIf(showInfoBanner)

            if let error = model.error, !error.localizedDescription.lowercased().contains("cancelled") {
                InfoBannerView(
                    description: error.localizedDescription,
                    type: .error,
                    leadingIcon: nil,
                    onClose: {
                        withAnimation { model.error = nil }
                    }
                )
            }

            usdcDepositedCard
        }
        .padding(.top, CircleConstants.Design.mainViewTopPadding)
        .padding(.bottom, CircleConstants.Design.mainViewBottomPadding)
        .padding(.horizontal, CircleConstants.Design.horizontalPadding)
    }

    var headerDescription: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 4) {
                Text(NSLocalizedString("circleDashboardDeposited", comment: "Deposited"))
                    .font(Theme.fonts.bodyLMedium)
                    .foregroundStyle(Theme.colors.textPrimary)

                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.colors.primaryAccent3)
                    .frame(height: 3)
            }
            .fixedSize(horizontal: true, vertical: false)

            Text(NSLocalizedString("circleDashboardDepositDescription", comment: "Deposit your $USDC..."))
                .font(Theme.fonts.bodyMRegular)
                .foregroundStyle(Theme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var topBanner: some View {
        ZStack(alignment: .trailing) {
            cardBackground

            // Decorative circles around the logo
            GeometryReader { geometry in
                ZStack {
                    Circle()
                        .stroke(Theme.colors.turquoise.opacity(0.25), lineWidth: 2)
                        .frame(width: 160, height: 160)

                    Circle()
                        .stroke(Theme.colors.turquoise.opacity(0.4), lineWidth: 4)
                        .frame(width: 120, height: 120)
                }
                .position(x: geometry.size.width - 50, y: geometry.size.height * 0.75)
            }
            .clipShape(RoundedRectangle(cornerRadius: CircleConstants.Design.cornerRadius))

            // Content
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("circleSetupAccountTitle", comment: "Circle USDC Account"))
                        .font(CircleConstants.Fonts.title)
                        .foregroundStyle(Theme.colors.textSecondary)

                    Text("$\(model.balance.formatted())")
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
                    .offset(x: 5, y: 27)
            }
            .padding(CircleConstants.Design.cardPadding)
        }
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
        VStack(spacing: 16) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "divide.circle")
                        .foregroundStyle(Theme.colors.textSecondary)
                    Text(NSLocalizedString("circleAPYLabel", comment: "APY (Approx.)"))
                        .font(CircleConstants.Fonts.subtitle)
                        .foregroundStyle(Theme.colors.textSecondary)
                }
                Spacer()
                Text("4.00%")
                    .font(CircleConstants.Fonts.subtitle)
                    .foregroundStyle(Theme.colors.turquoise)
            }

            HStack(spacing: 12) {
                DefiButton(
                    title: NSLocalizedString("circleDashboardWithdraw", comment: "Withdraw"),
                    icon: "minus.circle",
                    type: .outline,
                    isSystemIcon: true,
                    action: { router.navigate(to: CircleRoute.withdraw(vault: vault, model: model)) }
                )
                .disabled(model.balance <= 0)

                DefiButton(
                    title: NSLocalizedString("circleDashboardDeposit", comment: "Deposit"),
                    icon: "plus.circle",
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

        let (chain, _) = CircleViewLogic.getChainDetails()

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
