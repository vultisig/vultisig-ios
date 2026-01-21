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
    @Environment(\.dismiss) var dismiss

    @State var showInfoBanner = true
    @State var showError = false

    var walletUSDCBalance: Decimal {
        return CircleViewLogic.getWalletUSDCBalance(vault: vault)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: CircleConstants.Design.verticalSpacing) {
                    topBanner

                    VStack(alignment: .leading, spacing: 8) {
                        VStack(spacing: 8) {
                            Text("circleSetupDeposited".localized)
                                .font(Theme.fonts.bodySMedium)
                                .foregroundStyle(Theme.colors.textPrimary)
                            Rectangle()
                                .fill(Theme.colors.primaryAccent4)
                                .frame(height: 2)
                        }
                        .fixedSize()
                        Spacer()

                        Text("circleSetupDepositDescription".localized)
                            .font(Theme.fonts.bodySMedium)
                            .foregroundStyle(Theme.colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    InfoBannerView(
                        description: "circleSetupInfoText".localized,
                        type: .info,
                        leadingIcon: nil,
                        onClose: {
                            withAnimation { showInfoBanner = false }
                        }
                    )
                    .showIf(showInfoBanner)

                    bottomCard
                }
                .padding(.top, CircleConstants.Design.mainViewTopPadding)
                .padding(.bottom, CircleConstants.Design.mainViewBottomPadding)
                .padding(.horizontal, CircleConstants.Design.horizontalPadding)
            }
        }
        .background(VaultMainScreenBackground())
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

    var hasAccount: Bool {
        vault.circleWalletAddress != nil
    }

    var bottomCardLabel: String {
        if hasAccount || model.balance > 0 {
            return NSLocalizedString("circleSetupUSDCDeposited", comment: "USDC deposited")
        } else {
            return NSLocalizedString("circleSetupAccountBalance", comment: "Circle Account Balance")
        }
    }

    private var buttonTitle: String {
        model.isLoading
            ? NSLocalizedString("circleCreatingAccount", comment: "Creating account...")
            : NSLocalizedString("circleSetupOpenAccount", comment: "Open Account")
    }

    var bottomCard: some View {
        VStack(spacing: CircleConstants.Design.cardPadding) {
            HStack(spacing: 12) {
                Image("usdc")
                    .resizable()
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(bottomCardLabel)
                        .font(CircleConstants.Fonts.subtitle)
                        .foregroundStyle(Theme.colors.textSecondary)

                    Text("\(model.balance.formatted()) USDC")
                        .font(Theme.fonts.priceBodyL)
                        .foregroundStyle(Theme.colors.textPrimary)
                }
                Spacer()
            }

            PrimaryButton(
                title: buttonTitle,
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
                showError = true
            }
        }
    }
}
