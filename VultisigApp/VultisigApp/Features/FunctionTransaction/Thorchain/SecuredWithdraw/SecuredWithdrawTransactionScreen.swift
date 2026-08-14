//
//  SecuredWithdrawTransactionScreen.swift
//  VultisigApp
//
//  THORChain secured-asset redemption (`SECURE-`): pick a held secured asset,
//  the L1 address it pays out to, and how much. Continue is deliberately not
//  gated on `validForm` — see the doc comment on `FormScreen`;
//  `viewModel.transactionBuilder` returning nil is the enforcement, and the tap
//  is what reveals the errors on a form the user has not touched. It *is*
//  hard-disabled when the account holds no secured assets, which no field edit
//  can change.
//

import SwiftUI

struct SecuredWithdrawTransactionScreen: View {
    enum FocusedField {
        case asset, address, amount
    }

    @StateObject var viewModel: SecuredWithdrawTransactionViewModel
    var onVerify: (TransactionBuilder) -> Void

    @State var focusedFieldBinding: FocusedField?
    @FocusState private var focusedField: FocusedField?
    @State private var showAssetSelection: Bool = false

    var body: some View {
        FormScreen(
            title: "Withdraw Secured Asset".localized,
            fixedHeight: false,
            isContinueDisabled: viewModel.availableAssets.isEmpty,
            onContinue: onContinue
        ) {
            assetSection
            destinationSection
            amountSection
        }
        .onLoad {
            viewModel.onLoad()
            focusedFieldBinding = .asset
        }
        .delayedFocus(from: focusedFieldBinding, to: $focusedField)
        .crossPlatformSheet(isPresented: $showAssetSelection) {
            AssetSelectionListScreen(
                isPresented: $showAssetSelection,
                selectedAsset: $viewModel.selectedAsset,
                dataSource: viewModel.assetsDataSource
            ) {
                showAssetSelection = false
                viewModel.onAssetSelected()
                focusedFieldBinding = .address
            }
        }
    }

    // MARK: - Asset

    var assetSection: some View {
        FormExpandableSection(
            title: "asset".localized,
            isValid: viewModel.selectedAssetCoin != nil,
            value: viewModel.selectedAssetDisplayName,
            showValue: true,
            focusedField: $focusedFieldBinding,
            focusedFieldEquals: .asset
        ) {
            focusedFieldBinding = $0 ? .asset : nil
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                if viewModel.isLoadingAssets {
                    loadingAssetsView
                } else if let loadError = viewModel.loadError {
                    loadFailureView(message: loadError)
                } else {
                    assetPickerButton
                }
            }
        }
    }

    var loadingAssetsView: some View {
        HStack(spacing: 12) {
            SpinningLineLoader()
            Text("loadingSecuredAssets".localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
            Spacer()
        }
    }

    func loadFailureView(message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Icon(.circleInfo, color: Theme.colors.alertWarning, size: 14)
                Text(message)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.alertWarning)
                Spacer()
            }

            PrimaryButton(title: "retry".localized, type: .secondary, size: .small) {
                viewModel.loadAvailableSecuredAssets()
            }
        }
    }

    var assetPickerButton: some View {
        Button {
            showAssetSelection = true
        } label: {
            AssetSelectionFormCell(coin: viewModel.selectedAsset?.asset)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Destination

    var destinationSection: some View {
        FormExpandableSection(
            title: "destinationAddress".localized,
            isValid: viewModel.destinationField.valid,
            value: viewModel.destinationField.value,
            showValue: true,
            focusedField: $focusedFieldBinding,
            focusedFieldEquals: .address
        ) {
            focusedFieldBinding = $0 ? .address : nil
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                // `AddressTextField` rather than `FunctionAddressField`: the
                // chain this address belongs to is the secured asset's L1, so
                // it changes with the picker, and `AddressViewModel` takes its
                // coin as a `let` at init.
                AddressTextField(
                    address: $viewModel.destinationField.value,
                    label: viewModel.destinationField.label ?? .empty,
                    coin: viewModel.destinationCoin,
                    error: $viewModel.destinationField.error
                ) {
                    viewModel.handle(destinationAddressResult: $0)
                }
                .focused($focusedField, equals: .address)

                if let notice = viewModel.destinationNotice {
                    HStack(alignment: .top, spacing: 8) {
                        Icon(.circleInfo, color: Theme.colors.alertWarning, size: 14)
                        Text(notice)
                            .font(Theme.fonts.caption12)
                            .foregroundStyle(Theme.colors.alertWarning)
                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: - Amount

    var amountSection: some View {
        FormExpandableSection(
            title: viewModel.amountField.label ?? .empty,
            isValid: viewModel.amountField.valid,
            value: viewModel.amountField.value,
            showValue: true,
            focusedField: $focusedFieldBinding,
            focusedFieldEquals: .amount
        ) {
            focusedFieldBinding = $0 ? .amount : nil
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                CommonTextField(
                    text: $viewModel.amountField.value,
                    label: viewModel.amountField.label,
                    placeholder: viewModel.amountField.placeholder ?? .empty,
                    error: $viewModel.amountField.error,
                    labelStyle: .secondary
                )
#if os(iOS)
                .keyboardType(.decimalPad)
#endif
                .focused($focusedField, equals: .amount)

                Text(viewModel.balanceDescription)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
            }
        }
    }

    func onContinue() {
        // Nothing downstream can be judged before the asset is named, so the
        // first tap opens the picker rather than surfacing three errors that
        // all say the same thing.
        guard viewModel.selectedAsset != nil, !viewModel.availableAssets.isEmpty else {
            showAssetSelection = true
            return
        }
        guard let transactionBuilder = viewModel.transactionBuilder else {
            revealRefusal()
            return
        }
        onVerify(transactionBuilder)
    }

    /// Opens the section the refusal came from.
    ///
    /// `transactionBuilder` has just re-run every validator, so the errors are
    /// populated — but they render inside the expandable content, and a
    /// collapsed section shows none of it. Without this the tap is a dead
    /// button, which on the only route out of a secured position reads as
    /// "the app will not let me exit" with nothing saying why.
    func revealRefusal() {
        if viewModel.selectedAssetCoin == nil {
            showAssetSelection = true
        } else if !viewModel.destinationField.valid {
            focusedFieldBinding = .address
        } else {
            focusedFieldBinding = .amount
        }
    }
}

#Preview {
    SecuredWithdrawTransactionScreen(
        viewModel: SecuredWithdrawTransactionViewModel(
            coin: .example,
            vault: .example
        )
    ) { _ in }
}
