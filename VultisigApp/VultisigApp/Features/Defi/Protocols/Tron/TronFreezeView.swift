//
//  TronFreezeView.swift
//  VultisigApp
//
//  Created for TRON Freeze/Unfreeze integration
//

import SwiftUI
import BigInt

struct TronFreezeView: View {
    let vault: Vault
    @Environment(\.dismiss) var dismiss
    @Environment(\.router) var router

    @StateObject var tx = SendTransaction()
    @StateObject var sendCryptoViewModel = SendCryptoViewModel()
    @State var amount: String = ""
    @State var percentage: Double = 0.0
    @State var trxCoin: Coin?
    @State var error: Error?
    @State var isLoading = false
    @State var selectedResourceType: TronResourceType = .bandwidth

    var body: some View {
        content
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
    }

    var content: some View {
        Screen(
            title: NSLocalizedString("tronFreezeTitle", comment: "Freeze TRX"),
            showNavigationBar: true,
            backgroundType: .plain
        ) {
            ZStack {
                VStack(spacing: 0) {
                    scrollableContent
                    footerView
                }

                if isLoading {
                    Theme.colors.bgPrimary.opacity(0.8).ignoresSafeArea()
                    ProgressView()
                }
            }
        }
        .task {
            await loadData()
        }
    }

    var footerView: some View {
        VStack(spacing: 12) {
            if let error = error {
                Text(error.localizedDescription)
                    .foregroundStyle(Theme.colors.alertError)
                    .font(Theme.fonts.caption12)
            }

            freezeButton
        }
        .padding(TronConstants.Design.horizontalPadding)
        .background(Theme.colors.bgPrimary)
    }

    var freezeButton: some View {
        PrimaryButton(title: NSLocalizedString("tronFreezeContinue", comment: "Continue")) {
            Task { await handleContinue() }
        }
        .disabled(isButtonDisabled)
    }

    var isButtonDisabled: Bool {
        amount.isEmpty || amount.toDecimal() <= 0 || amount.toDecimal() > (trxCoin?.balanceDecimal ?? 0) || isLoading
    }

    var scrollableContent: some View {
        VStack(spacing: TronConstants.Design.verticalSpacing) {
            // Resource Type Picker
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("tronResourceType", comment: "Resource Type"))
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textSecondary)

                Picker("", selection: $selectedResourceType) {
                    ForEach(TronResourceType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("tronFreezeAmount", comment: "Amount"))
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textSecondary)

                    Divider()
                        .background(Theme.colors.textTertiary.opacity(0.2))
                }

                Spacer()

                VStack(spacing: 8) {
                    HStack(spacing: 4) {
                        amountTextField

                        Text("TRX")
                            .font(Theme.fonts.bodyLMedium)
                            .foregroundStyle(Theme.colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)

                    Text("\(Int(min(percentage, 100)))%")
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textSecondary)
                }

                Spacer()

                VStack(spacing: TronConstants.Design.verticalSpacing) {
                    percentageCheckpoints

                    HStack {
                        Text(NSLocalizedString("tronFreezeBalanceAvailable", comment: "Balance available:"))
                            .font(Theme.fonts.caption12)
                            .foregroundStyle(Theme.colors.textSecondary)

                        Spacer()

                        Text("\(trxCoin?.balanceString ?? "0") TRX")
                            .font(Theme.fonts.bodyMMedium)
                            .foregroundStyle(Theme.colors.textPrimary)
                    }
                }
            }
            .padding(TronConstants.Design.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: TronConstants.Design.cornerRadius)
                    .fill(Theme.colors.bgSurface1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: TronConstants.Design.cornerRadius)
                    .stroke(Theme.colors.textSecondary.opacity(0.2), lineWidth: 1)
            )
        }
        .padding(.horizontal, TronConstants.Design.horizontalPadding)
        .padding(.top, TronConstants.Design.verticalSpacing)
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
        guard let coin = vault.nativeCoin(for: .tron) else {
            await MainActor.run {
                self.error = TronStakingError.noTrxCoin
            }
            return
        }

        await BalanceService.shared.updateBalance(for: coin)

        await MainActor.run {
            self.trxCoin = coin
            tx.reset(coin: coin)
        }

        await sendCryptoViewModel.loadFastVault(tx: tx, vault: vault)
    }

    func updatePercentage(from amountStr: String) async {
        guard let coin = trxCoin, coin.balanceDecimal > 0 else {
            return
        }
        let amountDec = amountStr.toDecimal()
        let percent = (amountDec / coin.balanceDecimal) * 100
        let cappedPercent = min(Double(truncating: percent as NSNumber), 100.0)

        if abs(self.percentage - cappedPercent) > 0.1 {
            await MainActor.run {
                self.percentage = cappedPercent
            }
        }
    }

    func updateAmount(from percent: Double) {
        guard let coin = trxCoin else { return }
        let amountDec = coin.balanceDecimal * Decimal(percent) / 100
        let newAmount = amountDec.truncated(toPlaces: 6).description
        if self.amount != newAmount {
            self.amount = newAmount
        }
    }

    func handleContinue() async {
        let amountDec = amount.toDecimal()
        guard let coin = trxCoin, amountDec > 0 else {
            return
        }

        await MainActor.run { isLoading = true }

        // Configure SendTransaction for the freeze operation
        // The memo encodes the freeze operation type for TronHelper
        let memo = "FREEZE:\(selectedResourceType.tronResourceString)"

        await MainActor.run {
            tx.coin = coin
            tx.fromAddress = coin.address
            tx.toAddress = coin.address  // Freeze goes to self
            tx.amount = amountDec.description
            tx.memo = memo
            tx.isStakingOperation = true
        }

        await sendCryptoViewModel.loadFastVault(tx: tx, vault: vault)

        await MainActor.run {
            isLoading = false
            router.navigate(to: SendRoute.verify(tx: tx, vault: vault))
        }
    }
}
