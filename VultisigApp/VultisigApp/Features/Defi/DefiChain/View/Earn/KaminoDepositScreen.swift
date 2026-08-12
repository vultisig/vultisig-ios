//
//  KaminoDepositScreen.swift
//  VultisigApp
//
//  Asset-denominated deposit form for one curated Kamino Earn vault. On continue
//  it builds, validates and simulates the transaction, then routes to the shared
//  verify screen with the result as a pre-built payload — so what the user
//  approves is the exact bytes that were proven to execute.
//

import SwiftUI

struct KaminoDepositScreen: View {
    @StateObject private var viewModel: KaminoDepositViewModel
    @Environment(\.router) private var router

    @State private var percentageSelected: Double?
    @State private var error: HelperError?

    init(vault: Vault, descriptor: KaminoVaultDescriptor) {
        _viewModel = StateObject(
            wrappedValue: KaminoDepositViewModel(vault: vault, descriptor: descriptor)
        )
    }

    var body: some View {
        ZStack {
            if let coinMeta = viewModel.coinMeta {
                AmountFunctionTransactionScreen(
                    title: "kaminoDepositTitle".localized,
                    coin: coinMeta,
                    availableAmount: viewModel.availableAmount,
                    percentageSelected: $percentageSelected,
                    percentageFieldType: .button,
                    // The vault's own scale, not the form default of four: the
                    // SOL maximum is measured to the lamport, and truncating it
                    // for display would leave part of it undeposited.
                    amountDecimals: viewModel.descriptor.tokenDecimals,
                    amountField: viewModel.amountField,
                    validForm: $viewModel.validForm,
                    // Nothing the user can type makes a deposit possible when
                    // the wallet holds no coin for this vault's asset, when the
                    // vault's own minimum never arrived, or when the SOL reserve
                    // could not be measured. Those are the states the button
                    // must read as disabled in; a below-minimum or over-balance
                    // amount is not one of them — it is a field error the user
                    // can fix, and the button stays tappable so tapping it
                    // reveals the error.
                    isContinueDisabled: viewModel.isDepositUnavailable,
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
            minimumDepositBanner
            wrappedSolBanner
        }
    }

    /// The vault's own minimum. Shown rather than only enforced because the API
    /// accepts a below-minimum deposit and the chain rejects it afterwards, so
    /// this is the number that decides whether a deposit can work at all.
    @ViewBuilder
    private var minimumDepositBanner: some View {
        if viewModel.minimumDeposit != nil {
            InfoBannerView(
                description: viewModel.minimumDepositText,
                type: .info,
                leadingIcon: .circleInfo
            )
        }
    }

    /// A SOL deposit opens a wrapped-SOL account and leaves it open, so its rent
    /// stays locked up until the user withdraws. Disclosed on the form, not
    /// discovered from the balance afterwards.
    @ViewBuilder
    private var wrappedSolBanner: some View {
        if viewModel.showsWrappedSolNotice {
            InfoBannerView(
                description: "kaminoDepositWrappedSolRent".localized,
                type: .warning,
                leadingIcon: .circleInfo
            )
        }
    }

    @ViewBuilder
    private var missingCoinBanner: some View {
        if viewModel.isMissingDepositCoin {
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
        // network round trips cannot make them describe different deposits.
        guard let deposit = await viewModel.makeDeposit() else {
            if let buildError = viewModel.error {
                error = .runtimeError(buildError.localizedDescription)
            }
            return
        }

        router.navigate(
            to: SendRoute.verify(
                tx: deposit.transaction,
                retrySignal: SendRetrySignal(),
                vault: viewModel.vault,
                prebuiltKeysignPayload: deposit.payload
            )
        )
    }
}
