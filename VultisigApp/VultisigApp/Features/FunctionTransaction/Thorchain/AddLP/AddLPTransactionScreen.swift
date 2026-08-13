//
//  AddLPTransactionScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//

import SwiftUI

struct AddLPTransactionScreen: View {
    @StateObject var viewModel: AddLPTransactionViewModel
    var onVerify: (TransactionBuilder) -> Void

    @State private var showPoolSelection: Bool = false

    /// Reads and writes the view model's selection directly rather than
    /// mirroring it in local state. Picking a pool REASSIGNS THE ASSET THE
    /// DEPOSIT MOVES, so a second copy of that choice is a second answer to the
    /// question "what is being deposited"; the sheet's checkmark and the row's
    /// asset would also drift apart the moment the view model selects a pool
    /// itself, which it does when a chain offers only one.
    private var selectedPool: Binding<THORChainAsset?> {
        Binding(
            get: { viewModel.selectedPool },
            set: { pool in
                guard let pool else { return }
                viewModel.select(pool: pool)
            }
        )
    }

    var body: some View {
        AmountFunctionTransactionScreen(
            title: viewModel.title,
            coin: viewModel.coin.toCoinMeta(),
            availableAmount: viewModel.coin.balanceDecimal,
            percentageSelected: $viewModel.percentageSelected,
            percentageFieldType: .button,
            amountField: viewModel.amountField,
            customViewPosition: .bottom,
            onVerify: onContinue,
            customView: { asymmetricDepositInfo },
            topView: { poolSection }
        )
        .onLoad { viewModel.onLoad() }
        .onChange(of: viewModel.percentageSelected) { _, newValue in
            guard let newValue else { return }
            viewModel.onPercentage(newValue)
        }
        .withLoading(isLoading: $viewModel.isLoading)
        .crossPlatformSheet(isPresented: $showPoolSelection) {
            AssetSelectionListScreen(
                isPresented: $showPoolSelection,
                selectedAsset: selectedPool,
                dataSource: StaticAssetSelectionDataSource(assets: viewModel.pools)
            ) { showPoolSelection = false }
        }
    }

    func onContinue() {
        Task {
            guard let transactionBuilder = await viewModel.prepareTransactionBuilder() else { return }
            onVerify(transactionBuilder)
        }
    }

    /// The pool picker, and everything that can stop a deposit before an amount
    /// is even typed. Absent entirely for a deposit into an existing position,
    /// whose pool was decided by the card the user tapped.
    @ViewBuilder
    var poolSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.showsPoolPicker {
                poolPicker
            }
            if viewModel.canRetryPools {
                PrimaryButton(title: "retry", type: .secondary) {
                    viewModel.loadPools()
                }
            }
            if viewModel.showsApprovalInfo {
                approvalInfo
            }
            if let message = viewModel.blockingMessage {
                blockingNotice(message)
            }
            if !viewModel.isThorchainEnabled {
                PrimaryButton(title: "enableThorchain", isLoading: viewModel.isEnablingThorchain) {
                    Task { await viewModel.enableThorchain() }
                }
            }
        }
        .showIf(showsPoolSection)
    }

    var showsPoolSection: Bool {
        viewModel.showsPoolPicker
            || viewModel.canRetryPools
            || viewModel.showsApprovalInfo
            || viewModel.blockingMessage != nil
            || !viewModel.isThorchainEnabled
    }

    var poolPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("addLpPoolTitle".localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)

            Button {
                showPoolSelection = true
            } label: {
                Group {
                    if viewModel.isLoadingPools {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("loadingPools".localized)
                                .font(Theme.fonts.bodySMedium)
                                .foregroundStyle(Theme.colors.textTertiary)
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        .background(Theme.radius.pill.shape.fill(Theme.colors.bgSurface1))
                    } else if let pool = viewModel.selectedPool {
                        AssetSelectionFormCell(coin: pool.asset)
                    } else {
                        Text("addLpSelectPool".localized)
                            .font(Theme.fonts.bodySMedium)
                            .foregroundStyle(Theme.colors.textPrimary)
                            .padding(.vertical, 14)
                            .padding(.horizontal, 16)
                            .background(Theme.radius.pill.shape.fill(Theme.colors.bgSurface1))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.pools.isEmpty || viewModel.isLoadingPools)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var approvalInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("erc20ApprovalRequired".localized)
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.textPrimary)

            Text("approvalRequiredMessageLP".localized)
                .font(Theme.fonts.bodySRegular)
                .foregroundStyle(Theme.colors.textPrimary)

            VStack(alignment: .leading, spacing: 4) {
                Text("approvalTransaction".localized)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.primaryAccent1)
                Text("addLiquidityTransaction".localized)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.primaryAccent1)
            }
            .padding(.leading, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.colors.bgNeutral)
        .cornerRadius(Theme.radius.sm)
    }

    func blockingNotice(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Theme.colors.alertWarning)
                .font(Theme.fonts.caption12)
            Text(message)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textPrimary)
            Spacer()
        }
        .padding(12)
        .background(Theme.colors.bgNeutral)
        .cornerRadius(Theme.radius.sm)
    }

    @ViewBuilder
    var asymmetricDepositInfo: some View {
        if viewModel.showAsymmetricDepositInfo {
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(Theme.colors.alertInfo)
                    .font(Theme.fonts.caption12)
                VStack(alignment: .leading, spacing: 4) {
                    Text("asymmetricDeposit".localized)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textPrimary)
                    Text(viewModel.asymmetricDepositMessage)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textTertiary)
                }
                Spacer()
            }
            .padding(12)
            .background(Theme.colors.bgNeutral)
            .cornerRadius(Theme.radius.sm)
        }
    }
}

/// An `AssetSelectionDataSource` over an already-resolved list.
///
/// The pool list is loaded by the view model — it has to be, because picking a
/// pool reassigns the asset the deposit moves — so the picker is handed the
/// answer rather than fetching a second, possibly different one.
struct StaticAssetSelectionDataSource: AssetSelectionDataSource {
    let assets: [THORChainAsset]

    // swiftlint:disable:next async_without_await
    func fetchAssets() async -> [THORChainAsset] {
        assets
    }
}

#Preview {
    AddLPTransactionScreen(
        viewModel: AddLPTransactionViewModel.chain(coin: .example, vault: .example)
    ) { _ in }
}
