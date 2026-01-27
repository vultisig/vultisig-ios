//
//  CircleDepositView.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2025-12-13.
//

import SwiftUI
import BigInt
import WalletCore
import VultisigCommonData

struct CircleDepositView: View {
    let vault: Vault
    @Environment(\.dismiss) var dismiss
    @Environment(\.router) var router

    @StateObject var tx = SendTransaction()
    @StateObject var sendCryptoViewModel = SendCryptoViewModel()
    @State var amount: String = ""
    @State var percentage: Double = 0.0
    @State var usdcCoin: Coin?
    @State var error: Error?
    @State var isLoading = false

    var body: some View {
        content
    }

    var content: some View {
        Screen(
            title: NSLocalizedString("circleDepositTitle", comment: "Deposit to Circle Account"),
            showNavigationBar: true,
            backgroundType: .plain
        ) {
            VStack(spacing: 0) {
                scrollableContent
                footerView
            }
        }
        .withLoading(isLoading: $isLoading)
        .task {
            await loadData()
        }
    }

    var footerView: some View {
        VStack {
            if let error = error {
                Text(error.localizedDescription)
                    .foregroundStyle(Theme.colors.alertError)
                    .font(.caption)
                    .padding(.bottom, 8)
            }

            PrimaryButton(title: NSLocalizedString("circleDepositContinue", comment: "Continue")) {
                Task { await handleContinue() }
            }
            .disabled(isLoading || amount.isEmpty || (Decimal(string: amount) ?? 0) <= 0 || (Decimal(string: amount) ?? 0) > (usdcCoin?.balanceDecimal ?? 0))
        }
        .padding(CircleConstants.Design.horizontalPadding)
        .background(Theme.colors.bgPrimary)
    }

    var scrollableContent: some View {
        VStack(spacing: CircleConstants.Design.verticalSpacing) {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("circleDepositAmount", comment: "Amount"))
                        .font(CircleConstants.Fonts.subtitle)
                        .foregroundStyle(Theme.colors.textSecondary)

                    Divider()
                        .background(Theme.colors.textTertiary.opacity(0.2))
                }

                Spacer()

                VStack(spacing: 8) {
                    HStack(spacing: 4) {
                        amountTextField

                        Text("USDC")
                            .font(Theme.fonts.bodyLMedium)
                            .foregroundStyle(Theme.colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)

                    Text("\(Int(min(percentage, 100)))%")
                        .font(CircleConstants.Fonts.subtitle)
                        .foregroundStyle(Theme.colors.textSecondary)
                }

                Spacer()

                VStack(spacing: CircleConstants.Design.verticalSpacing) {
                    percentageCheckpoints

                    HStack {
                        Text(NSLocalizedString("circleDepositBalanceAvailable", comment: "Balance available:"))
                            .font(CircleConstants.Fonts.subtitle)
                            .foregroundStyle(Theme.colors.textSecondary)

                        Spacer()

                        Text("\(usdcCoin?.balanceString ?? "0") USDC")
                            .font(CircleConstants.Fonts.subtitle)
                            .bold()
                            .foregroundStyle(Theme.colors.textPrimary)
                    }
                }
            }
            .padding(CircleConstants.Design.cardPadding)

            .padding(.horizontal, CircleConstants.Design.horizontalPadding)
        }
        .padding(.top, CircleConstants.Design.verticalSpacing)
        .frame(maxHeight: .infinity)
    }

    var amountTextField: some View {
        SendCryptoAmountTextField(
            amount: $amount,
            onChange: { await updatePercentage(from: $0) }
        )
    }

    var percentageCheckpoints: some View {
        HStack(spacing: 8) {
            ForEach([25, 50, 75, 100], id: \.self) { value in
                PrimaryButton(
                    title: "\(value)%",
                    type: isPercentageSelected(value) ? .primary : .secondary,
                    size: .mini
                ) {
                    percentage = Double(value)
                    updateAmount(from: Double(value))
                }
            }
        }
    }

    func isPercentageSelected(_ value: Int) -> Bool {
        abs(percentage - Double(value)) < 1.0
    }

    func loadData() async {
        let (chain, _) = CircleViewLogic.getChainDetails(vault: vault)

        if let coin = vault.coins.first(where: { $0.chain == chain && $0.ticker == "USDC" }) {
            await BalanceService.shared.updateBalance(for: coin)

            await MainActor.run {
                self.usdcCoin = coin
                tx.reset(coin: coin)
            }
            await sendCryptoViewModel.loadFastVault(tx: tx, vault: vault)
        }
    }

    func updatePercentage(from amountStr: String) async {
        guard let coin = usdcCoin, let amountDec = Decimal(string: amountStr), coin.balanceDecimal > 0 else {
            return
        }
        let percent = (amountDec / coin.balanceDecimal) * 100
        let cappedPercent = min(Double(truncating: percent as NSNumber), 100.0)

        if abs(self.percentage - cappedPercent) > 0.1 {
            await MainActor.run {
                self.percentage = cappedPercent
            }
        }
    }

    func updateAmount(from percent: Double) {
        guard let coin = usdcCoin else { return }
        let amountDec = coin.balanceDecimal * Decimal(percent) / 100
        let newAmount = amountDec.truncated(toPlaces: 6).description
        if self.amount != newAmount {
            self.amount = newAmount
        }
    }

    func handleContinue() async {
        guard let coin = usdcCoin, let amountDec = Decimal(string: amount), let toAddress = vault.circleWalletAddress else {
            return
        }

        await MainActor.run { isLoading = true }

        tx.coin = coin
        tx.fromAddress = coin.address
        tx.toAddress = toAddress
        tx.amount = amountDec.description

        await sendCryptoViewModel.loadFastVault(tx: tx, vault: vault)

        await MainActor.run {
            isLoading = false
            router.navigate(to: SendRoute.verify(tx: tx, vault: vault))
        }
    }
}
