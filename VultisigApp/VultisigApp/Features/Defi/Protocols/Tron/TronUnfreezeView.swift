//
//  TronUnfreezeView.swift
//  VultisigApp
//
//  Created for TRON Freeze/Unfreeze integration
//

import SwiftUI
import BigInt

struct TronUnfreezeView: View {
    let vault: Vault
    @StateObject private var model: TronViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.router) var router

    @State var amount: String = ""
    @State var percentage: Double = 0.0
    @State var isLoading = false
    @State var error: Error?
    @State var selectedResourceType: TronResourceType = .bandwidth

    @StateObject var sendTransaction = SendTransaction()
    @StateObject var sendCryptoViewModel = SendCryptoViewModel()

    init(vault: Vault, model: TronViewModel) {
        self.vault = vault
        self._model = StateObject(wrappedValue: model)
    }

    var body: some View {
        content
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
    }

    var content: some View {
        Screen(
            title: NSLocalizedString("tronUnfreezeTitle", comment: "Unfreeze TRX"),
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
            if let error = error ?? model.error {
                Text(error.localizedDescription)
                    .foregroundStyle(Theme.colors.alertError)
                    .font(Theme.fonts.caption12)
            }

            unfreezeButton
        }
        .padding(TronConstants.Design.horizontalPadding)
        .background(Theme.colors.bgPrimary)
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
                .onChange(of: selectedResourceType) { _ in
                    Task {
                        await updatePercentage(from: amount)
                    }
                }
            }

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("tronUnfreezeAmount", comment: "Amount"))
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
                        Text(NSLocalizedString("tronUnfreezeBalanceAvailable", comment: "Frozen balance:"))
                            .font(Theme.fonts.caption12)
                            .foregroundStyle(Theme.colors.textSecondary)

                        Spacer()

                        Text("\(frozenBalanceForSelectedType.formatted()) TRX")
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

    var unfreezeButton: some View {
        PrimaryButton(title: NSLocalizedString("tronUnfreezeConfirm", comment: "Continue")) {
            Task { await handleUnfreeze() }
        }
        .disabled(isButtonDisabled)
    }

    var frozenBalanceForSelectedType: Decimal {
        switch selectedResourceType {
        case .bandwidth:
            return model.frozenBandwidthBalance
        case .energy:
            return model.frozenEnergyBalance
        }
    }

    var isButtonDisabled: Bool {
        amount.isEmpty || amount.toDecimal() <= 0 || amount.toDecimal() > frozenBalanceForSelectedType || isLoading
    }

    func loadData() async {
        do {
            let result = try await model.logic.fetchData(vault: vault)
            await MainActor.run {
                model.availableBalance = result.availableBalance
                model.frozenBandwidthBalance = result.frozenBandwidth
                model.frozenEnergyBalance = result.frozenEnergy
                model.unfreezingBalance = result.unfreezing
                model.pendingWithdrawals = result.pendingWithdrawals
                model.error = nil // Clear error on success
            }
        } catch {
            await MainActor.run {
                model.error = error
                self.isLoading = false
            }
        }
    }

    func updatePercentage(from amountStr: String) async {
        let balance = frozenBalanceForSelectedType
        let amountDec = amountStr.toDecimal()
        guard amountDec > 0, balance > 0 else {
            await MainActor.run {
                self.percentage = 0
            }
            return
        }
        let percent = (amountDec / balance) * 100
        let cappedPercent = min(Double(truncating: percent as NSNumber), 100.0)

        if abs(self.percentage - cappedPercent) > 0.1 {
            await MainActor.run {
                self.percentage = cappedPercent
            }
        }
    }

    func updateAmount(from percent: Double) {
        let balance = frozenBalanceForSelectedType
        guard balance > 0 else { return }
        let amountDec = balance * Decimal(percent) / 100
        let newAmount = amountDec.truncated(toPlaces: 6).description
        if self.amount != newAmount {
            self.amount = newAmount
        }
    }

    func handleUnfreeze() async {
        guard let amountDecimal = amount.parseInput(), amountDecimal > 0 else {
            return
        }

        guard let trxCoin = TronViewLogic.getTrxCoin(vault: vault) else {
            await MainActor.run { self.error = TronStakingError.noTrxCoin }
            return
        }

        await MainActor.run {
            isLoading = true
            error = nil
        }

        // Configure SendTransaction for the unfreeze operation
        // The memo encodes the unfreeze operation type for TronHelper
        let memo = "UNFREEZE:\(selectedResourceType.tronResourceString)"

        await MainActor.run {
            sendTransaction.coin = trxCoin
            sendTransaction.fromAddress = trxCoin.address
            sendTransaction.toAddress = trxCoin.address  // Unfreeze returns to self
            sendTransaction.amount = amountDecimal.description
            sendTransaction.memo = memo
            sendTransaction.isStakingOperation = true
        }

        await sendCryptoViewModel.loadFastVault(tx: sendTransaction, vault: vault)

        await MainActor.run {
            isLoading = false
            router.navigate(to: SendRoute.verify(tx: sendTransaction, vault: vault))
        }
    }
}
