//
//  YieldDepositScreen.swift
//  VultisigApp
//

import SwiftUI

/// Deposit form for a yield vault. Reuses the shared amount screen; on continue
/// it builds ONE prebuilt EVM payload that bundles the approve+deposit and routes
/// to the shared verify screen.
struct YieldDepositScreen: View {
    @StateObject private var viewModel: YieldDepositViewModel
    @Environment(\.router) private var router

    @State private var percentageSelected: Double?
    @State private var error: HelperError?

    init(vault: Vault, providerID: DefiYieldProviderID) {
        _viewModel = StateObject(wrappedValue: YieldDepositViewModel(vault: vault, providerID: providerID))
    }

    var body: some View {
        ZStack {
            if let coinMeta = viewModel.coinMeta {
                AmountFunctionTransactionScreen(
                    title: viewModel.provider.presentation.depositTitleKey.localized,
                    coin: coinMeta,
                    availableAmount: viewModel.availableAmount,
                    percentageSelected: $percentageSelected,
                    percentageFieldType: .button,
                    amountField: viewModel.amountField,
                    validForm: $viewModel.validForm,
                    customViewPosition: .bottom
                ) {
                    Task { await handleVerify() }
                } customView: {
                    customView
                }
            }
        }
        .withLoading(isLoading: $viewModel.isLoading)
        .task {
            await viewModel.onLoad()
        }
        .alert(item: $error) { error in
            Alert(
                title: Text("error".localized),
                message: Text(error.localizedDescription),
                dismissButton: .default(Text("ok".localized))
            )
        }
    }

    private var customView: some View {
        VStack(spacing: 12) {
            yieldPreview
            minimumDepositBanner
        }
    }

    /// Estimated-yield preview: the entered amount projected over a month and a
    /// year at the provider's 7d-net APY. Hidden until both an amount and an APY
    /// are available.
    @ViewBuilder
    private var yieldPreview: some View {
        if viewModel.showsYieldPreview {
            VStack(spacing: 8) {
                yieldPreviewRow(label: "yieldEstMonthly", value: viewModel.estimatedMonthlyText)
                yieldPreviewRow(label: "yieldEstYearly", value: viewModel.estimatedYearlyText)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.colors.bgSurface1)
            )
        }
    }

    private func yieldPreviewRow(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label.localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textTertiary)
            Spacer()
            AmountText(value)
                .font(Theme.fonts.priceBodyS)
                .foregroundStyle(Theme.colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Non-closable info banner stating the product minimum (e.g. "Minimum deposit
    /// is 100 USDC."). Shown only for providers that declare a minimum.
    @ViewBuilder
    private var minimumDepositBanner: some View {
        if viewModel.hasMinimumDeposit {
            InfoBannerView(
                description: viewModel.minimumDepositText,
                type: .info,
                leadingIcon: "circle-info"
            )
        }
    }

    private func handleVerify() async {
        guard let payload = await viewModel.makeDepositPayload(),
              let displayTx = viewModel.displayTransaction() else {
            await MainActor.run {
                if let buildError = viewModel.error {
                    error = .runtimeError(buildError.localizedDescription)
                }
            }
            return
        }

        await MainActor.run {
            router.navigate(
                to: SendRoute.verify(
                    tx: displayTx,
                    retrySignal: SendRetrySignal(),
                    vault: viewModel.vault,
                    prebuiltKeysignPayload: payload
                )
            )
        }
    }
}
