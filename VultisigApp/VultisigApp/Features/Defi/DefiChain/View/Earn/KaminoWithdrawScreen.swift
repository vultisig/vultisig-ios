//
//  KaminoWithdrawScreen.swift
//  VultisigApp
//
//  Asset-denominated withdraw form for one curated Kamino Earn vault. On
//  continue it converts the asset amount to shares, then builds, validates and
//  simulates the transaction and routes to the shared verify screen with the
//  result as a pre-built payload — so what the user approves is the exact bytes
//  that were proven to execute.
//
//  The screen exists even for positions it cannot withdraw. A farm-staked
//  position is the state every real deposit into these vaults is in, and saying
//  so where the user looked for the button is better than having no button at
//  all and no explanation.
//

import SwiftUI

struct KaminoWithdrawScreen: View {
    @StateObject private var viewModel: KaminoWithdrawViewModel
    @Environment(\.router) private var router

    @State private var percentageSelected: Double?
    @State private var error: HelperError?

    init(vault: Vault, descriptor: KaminoVaultDescriptor) {
        _viewModel = StateObject(
            wrappedValue: KaminoWithdrawViewModel(vault: vault, descriptor: descriptor)
        )
    }

    var body: some View {
        ZStack {
            if let coinMeta = viewModel.coinMeta {
                AmountFunctionTransactionScreen(
                    title: "kaminoWithdrawTitle".localized,
                    coin: coinMeta,
                    availableAmount: viewModel.availableAmount,
                    percentageSelected: $percentageSelected,
                    percentageFieldType: .button,
                    // The vault's own scale, not the form default of four. The
                    // 100% button writes this field, and a truncated maximum
                    // would read as less than the position — the amount sent is
                    // the exact share balance either way, but the number on
                    // screen has to match it.
                    amountDecimals: viewModel.descriptor.tokenDecimals,
                    amountField: viewModel.amountField,
                    // A position that cannot be withdrawn at all — staked in the
                    // vault's farm, empty, or unreadable — is a state no amount
                    // satisfies, so the button reads as disabled rather than
                    // refusing after the tap.
                    isContinueDisabled: viewModel.unavailableReason != nil,
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
            missingCoinBanner
            unavailableBanner
            minimumWithdrawBanner
            liquidityBanner
        }
    }

    /// Why this position cannot be withdrawn — most often that it is staked in
    /// the vault's farm. Shown as information rather than as an error: it is a
    /// fact about the position, not something the user did.
    @ViewBuilder
    private var unavailableBanner: some View {
        if let reason = viewModel.unavailableReason {
            InfoBannerView(
                description: reason.localizedDescription,
                type: .warning,
                leadingIcon: .circleInfo
            )
        }
    }

    /// The vault's own minimum, converted into the asset the form is
    /// denominated in. Shown rather than only enforced because the API accepts a
    /// below-minimum withdraw and the chain rejects it afterwards.
    @ViewBuilder
    private var minimumWithdrawBanner: some View {
        if viewModel.unavailableReason == nil, viewModel.minimumWithdraw != nil {
            InfoBannerView(
                description: viewModel.minimumWithdrawText,
                type: .info,
                leadingIcon: .circleInfo
            )
        }
    }

    /// What the vault can settle out of its liquid balance right now. An
    /// ordinary state, not an exception — the buffer is a fraction of a percent
    /// of either vault, so most withdraws of any size exceed it.
    @ViewBuilder
    private var liquidityBanner: some View {
        if let text = viewModel.limitedLiquidityText {
            InfoBannerView(
                description: text,
                type: .warning,
                leadingIcon: .circleInfo
            )
        }
    }

    @ViewBuilder
    private var missingCoinBanner: some View {
        if viewModel.isMissingWithdrawCoin {
            InfoBannerView(
                description: viewModel.missingCoinText,
                type: .warning,
                leadingIcon: .circleInfo
            )
        }
    }

    private func handleVerify() async {
        // One call, one reading of the amount: the summary and the payload it
        // approves are built from the same value, so an edit landing during the
        // network round trips cannot make them describe different withdrawals.
        guard let withdraw = await viewModel.makeWithdraw() else {
            if let buildError = viewModel.error {
                error = .runtimeError(buildError.localizedDescription)
            }
            return
        }

        router.navigate(
            to: SendRoute.verify(
                tx: withdraw.transaction,
                retrySignal: SendRetrySignal(),
                vault: viewModel.vault,
                prebuiltKeysignPayload: withdraw.payload
            )
        )
    }
}
