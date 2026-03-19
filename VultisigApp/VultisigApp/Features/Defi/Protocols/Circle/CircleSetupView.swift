//
//  CircleSetupView.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2025-12-11.
//

import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.vultisig.app", category: "circle-setup")

struct CircleSetupView: View {
    let vault: Vault
    @ObservedObject var model: CircleViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.router) var router

    @AppStorage("appClosedBanners") var appClosedBanners: [String] = []
    @State private var showRewardsTooltip = false
    @State private var showError = false

    private let infoBannerId = "circleDashboardInfoBanner"

    var hasAccount: Bool {
        vault.circleWalletAddress != nil
    }

    var walletUSDCBalance: Decimal {
        CircleViewLogic.getWalletUSDCBalance(vault: vault)
    }

    var showInfoBanner: Bool {
        !appClosedBanners.contains(infoBannerId)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: CircleConstants.Design.verticalSpacing) {
                topBanner

                headerDescription

                InfoBannerView(
                    description: NSLocalizedString("circleDashboardInfoText", comment: "Funds remain..."),
                    type: .info,
                    leadingIcon: nil,
                    onClose: {
                        withAnimation { appClosedBanners.append(infoBannerId) }
                    }
                )
                .showIf(showInfoBanner)

                if hasAccount, let error = model.error,
                   !error.localizedDescription.lowercased().contains("cancelled") {
                    InfoBannerView(
                        description: error.localizedDescription,
                        type: .error,
                        leadingIcon: nil,
                        onClose: {
                            withAnimation { model.error = nil }
                        }
                    )
                }

                bottomCard
            }
            .padding(.top, CircleConstants.Design.mainViewTopPadding)
            .padding(.bottom, CircleConstants.Design.mainViewBottomPadding)
        }
        .background(VaultMainScreenBackground())
        #if os(iOS)
        .refreshable {
            guard hasAccount else { return }
            await loadData()
        }
        #endif
        .onAppear {
            guard hasAccount else { return }
            Task { await loadData() }
        }
        .alert(isPresented: $showError) {
            Alert(
                title: Text(NSLocalizedString("error", comment: "Error")),
                message: Text(model.error?.localizedDescription ?? NSLocalizedString("somethingWentWrongTryAgain", comment: "Something went wrong")),
                dismissButton: .default(Text(NSLocalizedString("ok", comment: "OK"))) {
                    model.error = nil
                }
            )
        }
    }

    // MARK: - Top Banner

    var topBanner: some View {
        ZStack(alignment: .trailing) {
            cardBackground

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

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("circleSetupAccountTitle", comment: "Circle USDC Account"))
                        .font(Theme.fonts.bodyLMedium)
                        .foregroundStyle(Theme.colors.textPrimary)

                    if hasAccount {
                        HiddenBalanceText("$\(model.balance.formatted())")
                            .font(CircleConstants.Fonts.balance)
                            .foregroundStyle(Theme.colors.textPrimary)
                    } else {
                        Text("$\(walletUSDCBalance.formatted())")
                            .font(CircleConstants.Fonts.balance)
                            .foregroundStyle(Theme.colors.textPrimary)
                    }
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

    // MARK: - Header Description

    var headerDescription: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 4) {
                Text(NSLocalizedString("circleDashboardDeposited", comment: "Deposited"))
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textPrimary)

                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.colors.primaryAccent3)
                    .frame(height: 3)
            }
            .fixedSize(horizontal: true, vertical: false)

            Text(NSLocalizedString("circleDashboardDepositDescription", comment: "Deposit your $USDC..."))
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Bottom Card

    @ViewBuilder
    var bottomCard: some View {
        if hasAccount {
            depositedCard
        } else {
            setupCard
        }
    }

    // MARK: - Deposited Card (account state)

    private var depositedCard: some View {
        VStack(spacing: 16) {
            usdcBalanceSection

            Separator(color: Theme.colors.borderLight, opacity: 1)
            
            apyRow

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

    private var usdcBalanceSection: some View {
        HStack(spacing: 12) {
            Image("usdc")
                .resizable()
                .frame(width: 40, height: 40)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString("circleUSDCDeposited", comment: "USDC deposited"))
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textSecondary)

                HiddenBalanceText("\(model.balance.formatted()) USDC")
                    .font(Theme.fonts.priceTitle1)
                    .foregroundStyle(Theme.colors.textPrimary)

                HiddenBalanceText("$\(model.balance.formatted())")
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textSecondary)
            }

            Spacer()
        }
    }

    private var apyRow: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "divide.circle")
                    .foregroundStyle(Theme.colors.textTertiary)

                Text(NSLocalizedString("circleAPYLabel", comment: "APY (Approx.)"))
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textTertiary)

//                rewardsTooltipButton
            }

            Spacer()

            Text("1%")
                .font(CircleConstants.Fonts.subtitle)
                .foregroundStyle(Theme.colors.turquoise)
        }
    }

    private var rewardsTooltipButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showRewardsTooltip.toggle()
            }
        } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(Theme.colors.textSecondary)
                .font(.system(size: 14))
        }
        .overlay(alignment: .top) {
            if showRewardsTooltip {
                rewardsTooltipContent
                    .offset(y: 28)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            }
        }
    }

    private var rewardsTooltipContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Text(NSLocalizedString("circleRewardsTitle", comment: "Rewards"))
                    .font(Theme.fonts.bodyMMedium)
                    .foregroundStyle(Theme.colors.textDark)

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showRewardsTooltip = false
                    }
                } label: {
                    Icon(named: "x", color: Theme.colors.textButtonDisabled, size: 20)
                }
            }

            Text(NSLocalizedString("circleRewardsDescription", comment: "Rewards are automatically credited to your balance."))
                .font(Theme.fonts.footnote)
                .foregroundStyle(Theme.colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .background(Color(hex: "F5F5F5"))
        .clipShape(TooltipShape())
        .frame(maxWidth: 220)
    }

    // MARK: - Setup Card (no account state)

    private var setupCard: some View {
        VStack(spacing: CircleConstants.Design.cardPadding) {
            HStack(spacing: 12) {
                Image("usdc")
                    .resizable()
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(setupCardLabel)
                        .font(CircleConstants.Fonts.subtitle)
                        .foregroundStyle(Theme.colors.textSecondary)

                    Text("\(model.balance.formatted()) USDC")
                        .font(Theme.fonts.priceBodyL)
                        .foregroundStyle(Theme.colors.textPrimary)
                }
                Spacer()
            }

            PrimaryButton(
                title: setupButtonTitle,
                isLoading: model.isLoading,
                type: .primary,
                size: .medium
            ) {
                Task { await createWallet() }
            }
            .disabled(model.isLoading)
        }
        .padding(CircleConstants.Design.cardPadding)
        .background(cardBackground)
    }

    private var setupCardLabel: String {
        model.balance > 0
            ? NSLocalizedString("circleSetupUSDCDeposited", comment: "USDC deposited")
            : NSLocalizedString("circleSetupAccountBalance", comment: "Circle Account Balance")
    }

    private var setupButtonTitle: String {
        model.isLoading
            ? NSLocalizedString("circleCreatingAccount", comment: "Creating account...")
            : NSLocalizedString("circleSetupOpenAccount", comment: "Open Account")
    }

    // MARK: - Card Background

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

    // MARK: - Actions

    private func loadData() async {
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
            logger.error("Error loading Circle data: \(error.localizedDescription)")
            await MainActor.run {
                model.error = error
            }
        }
    }

    private func createWallet() async {
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
                showError = true
            }
        }
    }
}
