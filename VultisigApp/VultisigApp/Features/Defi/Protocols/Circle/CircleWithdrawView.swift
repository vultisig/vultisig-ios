//
//  CircleWithdrawView.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2025-12-13.
//

import SwiftUI
import BigInt
import WalletCore
import VultisigCommonData

struct CircleWithdrawView: View {
    let vault: Vault
    @StateObject private var model: CircleViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.router) var router

    @State var amount: String = ""
    @State var percentage: Double = 0.0
    @State var isLoading = false
    @State var error: Error?
    @State var isFastVault = false
    @State var fastPasswordPresented = false
    @State var fastVaultPassword: String = ""

    @StateObject var sendTransaction = SendTransaction()

    init(vault: Vault, model: CircleViewModel) {
        self.vault = vault
        self._model = StateObject(wrappedValue: model)
    }

    var body: some View {
        content
    }

    var content: some View {
        Screen(
            title: NSLocalizedString("circleWithdrawTitle", comment: "Withdraw from Circle"),
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
            await loadFastVaultStatus()
        }
        .crossPlatformSheet(isPresented: $fastPasswordPresented) {
            FastVaultEnterPasswordView(
                password: $fastVaultPassword,
                vault: vault,
                onSubmit: { Task { await handleWithdraw() } }
            )
        }
    }

    var footerView: some View {
        VStack(spacing: 12) {
            if let error = error {
                Text(error.localizedDescription)
                    .foregroundStyle(Theme.colors.alertError)
                    .font(.caption)
            }

            if vaultEthBalance <= 0 {
                Text(NSLocalizedString("circleDashboardETHRequired", comment: "ETH is required..."))
                    .font(.caption)
                    .foregroundStyle(Theme.colors.alertWarning)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            withdrawButton
        }
        .padding(CircleConstants.Design.horizontalPadding)
        .background(Theme.colors.bgPrimary)
    }

    var scrollableContent: some View {
        VStack(spacing: CircleConstants.Design.verticalSpacing) {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("circleWithdrawAmount", comment: "Amount"))
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

                        Text("\(model.balance.formatted()) USDC")
                            .font(CircleConstants.Fonts.subtitle)
                            .bold()
                            .foregroundStyle(Theme.colors.textPrimary)
                    }
                }
            }
            .padding(CircleConstants.Design.cardPadding)
            .overlay(
                RoundedRectangle(cornerRadius: CircleConstants.Design.cornerRadius)
                    .stroke(Theme.colors.textSecondary.opacity(0.2), lineWidth: 1)
            )
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

    @ViewBuilder
    var withdrawButton: some View {
        if isFastVault {
            VStack {
                Text(NSLocalizedString("holdForPairedSign", comment: ""))
                    .foregroundColor(Theme.colors.textTertiary)
                    .font(Theme.fonts.bodySMedium)

                LongPressPrimaryButton(title: NSLocalizedString("circleWithdrawConfirm", comment: "Continue")) {
                    fastPasswordPresented = true
                } longPressAction: {
                    fastVaultPassword = ""
                    Task { await handleWithdraw() }
                }
            }
            .disabled(isButtonDisabled)
        } else {
            PrimaryButton(title: NSLocalizedString("circleWithdrawConfirm", comment: "Continue")) {
                Task { await handleWithdraw() }
            }
            .disabled(isButtonDisabled)
        }
    }

    var vaultEthBalance: Decimal {
        let (chain, _) = CircleViewLogic.getChainDetails(vault: vault)
        return vault.coins.first(where: { $0.chain == chain && $0.isNativeToken })?.balanceDecimal ?? 0
    }

    var isButtonDisabled: Bool {
        amount.isEmpty || (Decimal(string: amount) ?? 0) <= 0 || (Decimal(string: amount) ?? 0) > model.balance || vaultEthBalance <= 0 || isLoading
    }

    func loadFastVaultStatus() async {
        let isExist = await FastVaultService.shared.exist(pubKeyECDSA: vault.pubKeyECDSA)
        let isLocalBackup = vault.localPartyID.lowercased().contains("server-")

        await MainActor.run {
            isFastVault = isExist && !isLocalBackup
        }
    }

    func updatePercentage(from amountStr: String) async {
        let balance = model.balance
        guard let amountDec = Decimal(string: amountStr), balance > 0 else {
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
        let balance = model.balance
        guard balance > 0 else { return }
        let amountDec = balance * Decimal(percent) / 100
        let newAmount = amountDec.truncated(toPlaces: 6).description
        if self.amount != newAmount {
            self.amount = newAmount
        }
    }

    func handleWithdraw() async {
        guard let amountDecimal = Decimal(string: amount) else {
            await MainActor.run {
                isLoading = false
            }
            return
        }

        await MainActor.run {
            isLoading = true
            error = nil
        }

        do {
            let decimals = 6
            let amountUnits = (amountDecimal * pow(10, decimals)).description
            let cleanAmountUnits = amountUnits.components(separatedBy: ".").first ?? amountUnits
            let amountVal = BigInt(cleanAmountUnits) ?? BigInt(0)

            let (chain, _) = CircleViewLogic.getChainDetails(vault: vault)
            guard let recipientCoin = vault.coins.first(where: { $0.chain == chain && $0.isNativeToken }) else {
                throw NSError(domain: "CircleWithdraw", code: 404, userInfo: [NSLocalizedDescriptionKey: "ETH address not found"])
            }

            // Use USDC coin for display purposes on success screen
            guard let usdcCoin = vault.coins.first(where: { $0.chain == chain && $0.ticker == "USDC" }) else {
                throw NSError(domain: "CircleWithdraw", code: 404, userInfo: [NSLocalizedDescriptionKey: "USDC coin not found"])
            }

            func attemptPayload() async throws -> KeysignPayload {
                return try await model.logic.getWithdrawalPayload(
                    vault: vault,
                    recipient: recipientCoin.address,
                    amount: amountVal
                )
            }

            let payload: KeysignPayload
            do {
                payload = try await attemptPayload()
            } catch let err as CircleServiceError {
                if case .walletNotDeployed = err {
                    do {
                        _ = try await CircleApiService.shared.createWallet(
                            ethAddress: recipientCoin.address
                        )
                    } catch {
                        print("Circle create wallet error: \(error.localizedDescription)")
                    }
                    payload = try await attemptPayload()
                } else {
                    throw err
                }
            } catch {
                throw error
            }

            await MainActor.run {
                self.sendTransaction.reset(coin: usdcCoin)
                self.sendTransaction.isFastVault = isFastVault
                self.sendTransaction.fastVaultPassword = fastVaultPassword

                router.navigate(
                    to: SendRoute.pairing(
                        vault: vault,
                        tx: sendTransaction,
                        keysignPayload: payload,
                        fastVaultPassword: fastVaultPassword.nilIfEmpty
                    )
                )

                isLoading = false
            }

        } catch {
            await MainActor.run {
                self.error = error
                self.isLoading = false
            }
        }
    }
}
