//
//  YieldWithdrawView.swift
//  VultisigApp
//

import OSLog
import SwiftUI
import BigInt

private let logger = Logger(subsystem: "com.vultisig.app", category: "yield-withdraw-view")

/// Generic withdraw form for a yield vault. Builds the withdraw/requestRedeem
/// payload (chosen by liquidity) and routes to the shared verify screen with a
/// display-only USDC transaction.
struct YieldWithdrawView: View {
    @StateObject private var viewModel: YieldWithdrawViewModel
    @Environment(\.router) private var router

    @MainActor
    init(vault: Vault, providerID: DefiYieldProviderID, model: YieldViewModel) {
        _viewModel = StateObject(
            wrappedValue: YieldWithdrawViewModel(
                vault: vault,
                providerID: providerID,
                availableBalance: model.depositedBalance
            )
        )
    }

    var body: some View {
        Screen {
            VStack(spacing: 0) {
                scrollableContent
                footerView
            }
        }
        .screenTitle("noonWithdrawTitle".localized)
        .withLoading(isLoading: $viewModel.isLoading)
    }

    private var scrollableContent: some View {
        VStack(spacing: NoonConstants.Design.verticalSpacing) {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("noonWithdrawAmountLabel".localized)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textSecondary)
                    Divider()
                        .background(Theme.colors.textTertiary.opacity(0.2))
                }

                Spacer()

                VStack(spacing: 8) {
                    HStack(spacing: 4) {
                        SendCryptoAmountTextField(
                            amount: $viewModel.amount,
                            onChange: { viewModel.updatePercentage(from: $0) }
                        )
                        .fixedSize()
                        Text("USDC")
                            .font(Theme.fonts.bodyLMedium)
                            .foregroundStyle(Theme.colors.textSecondary)
                    }
                    Text("\(Int(min(viewModel.percentage, 100)))%")
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textSecondary)
                }

                Spacer()

                VStack(spacing: NoonConstants.Design.verticalSpacing) {
                    percentageCheckpoints
                    HStack {
                        Text("noonWithdrawBalanceAvailable".localized)
                            .font(Theme.fonts.caption12)
                            .foregroundStyle(Theme.colors.textSecondary)
                        Spacer()
                        Text("\(viewModel.availableBalance.formatted()) USDC")
                            .font(Theme.fonts.caption12)
                            .bold()
                            .foregroundStyle(Theme.colors.textPrimary)
                    }
                }
            }
            .padding(NoonConstants.Design.cardPadding)
            .overlay(
                RoundedRectangle(cornerRadius: NoonConstants.Design.cornerRadius)
                    .stroke(Theme.colors.textSecondary.opacity(0.2), lineWidth: 1)
            )
            .padding(.horizontal, NoonConstants.Design.horizontalPadding)
        }
        .padding(.top, NoonConstants.Design.verticalSpacing)
        .frame(maxHeight: .infinity)
    }

    private var percentageCheckpoints: some View {
        HStack(spacing: 8) {
            ForEach([25, 50, 75, 100], id: \.self) { value in
                PrimaryButton(
                    title: "\(value)%",
                    type: abs(viewModel.percentage - Double(value)) < 1 ? .primary : .secondary,
                    size: .mini
                ) {
                    viewModel.percentage = Double(value)
                    viewModel.updateAmount(from: Double(value))
                }
            }
        }
    }

    private var footerView: some View {
        VStack(spacing: 12) {
            if let error = viewModel.error {
                Text(error.localizedDescription)
                    .foregroundStyle(Theme.colors.alertError)
                    .font(.caption)
            }
            Text("noonRedemptionWindowNote".localized)
                .font(.caption)
                .foregroundStyle(Theme.colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if viewModel.nativeGasBalance <= 0 {
                Text("noonDashboardETHRequired".localized)
                    .font(.caption)
                    .foregroundStyle(Theme.colors.alertWarning)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            PrimaryButton(title: "noonWithdrawConfirm".localized) {
                Task { await handleWithdraw() }
            }
            .disabled(viewModel.isButtonDisabled)
        }
        .padding(NoonConstants.Design.horizontalPadding)
        .background(Theme.colors.bgPrimary)
    }

    private func handleWithdraw() async {
        guard let result = await viewModel.buildPayload(),
              let displayTx = viewModel.displayTransaction(recipient: result.recipient) else { return }

        await MainActor.run {
            router.navigate(
                to: SendRoute.verify(
                    tx: displayTx,
                    retrySignal: SendRetrySignal(),
                    vault: viewModel.vault,
                    prebuiltKeysignPayload: result.payload
                )
            )
        }
    }
}
