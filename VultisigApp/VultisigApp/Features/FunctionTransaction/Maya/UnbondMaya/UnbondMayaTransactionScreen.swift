//
//  UnbondMayaTransactionScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/11/2025.
//

import SwiftUI

struct UnbondMayaTransactionScreen: View {
    enum FocusedField {
        case address, amount
    }
    
    @StateObject var viewModel: UnbondMayaTransactionViewModel
    var onVerify: (TransactionBuilder) -> Void
    
    @State var focusedFieldBinding: FocusedField? = .none
    @FocusState private var focusedField: FocusedField?
    
    @State var showAssetSelection: Bool = false
    
    var body: some View {
        FormScreen(
            title: "unbond".localized,
            validForm: $viewModel.validForm,
            onContinue: onContinue
        ) {
            FormExpandableSection(
                title: "address".localized,
                isValid: viewModel.addressViewModel.field.valid,
                value: viewModel.addressViewModel.field.value,
                showValue: true,
                focusedField: $focusedFieldBinding,
                focusedFieldEquals: .address
            ) {
                focusedFieldBinding = $0 ? .address : .amount
            } content: {
                FunctionAddressField(viewModel: viewModel.addressViewModel)
                    .focused($focusedField, equals: .address)
            }

            FormExpandableSection(
                title: "asset".localized,
                isValid: viewModel.lpUnitsField.valid,
                value: .empty,
                showValue: false,
                focusedField: $focusedFieldBinding,
                focusedFieldEquals: .amount
            ) {
                focusedFieldBinding = $0 ? .amount : .address
            } content: {
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        showAssetSelection = true
                    } label: {
                        AssetSelectionFormCell(coin: viewModel.selectedAsset?.asset)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    CommonTextField(
                        text: $viewModel.lpUnitsField.value,
                        label: viewModel.lpUnitsField.label,
                        placeholder: viewModel.lpUnitsField.placeholder ?? .empty,
                        error: $viewModel.lpUnitsField.error,
                        labelStyle: .secondary
                    )
                    .focused($focusedField, equals: .amount)
#if os(iOS)
                    .keyboardType(.decimalPad)
#endif

                    // Bonded LP units display
                    if let bondedUnits = viewModel.bondedLPUnits {
                        HStack {
                            Text("bondedLPUnits".localized)
                                .font(Theme.fonts.caption12)
                                .foregroundColor(Theme.colors.textTertiary)
                            Spacer()
                            Text(bondedUnits)
                                .font(Theme.fonts.caption12)
                                .foregroundColor(Theme.colors.textPrimary)
                            Button(action: {
                                viewModel.lpUnitsField.value = bondedUnits
                            }) {
                                Text("max".localized)
                                    .font(Theme.fonts.caption12)
                                    .foregroundColor(Theme.colors.alertInfo)
                            }
                        }
                    }

                    // Estimated CACAO value
                    if let cacaoValue = viewModel.estimatedCacaoValue {
                        HStack {
                            Text("estimatedCacaoValue".localized)
                                .font(Theme.fonts.caption12)
                                .foregroundColor(Theme.colors.textTertiary)
                            Spacer()
                            Text("\(cacaoValue.formatted()) CACAO")
                                .font(Theme.fonts.caption12)
                                .foregroundColor(Theme.colors.textPrimary)
                        }
                    }
                }
            }
        }
        .onLoad {
            viewModel.onLoad()
            onAddressFill()
        }
        .onChange(of: viewModel.addressViewModel.field.valid) { _, _ in
            onAddressFill()
        }
        .onChange(of: focusedFieldBinding) { _, newValue in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                focusedField = newValue
            }
        }
        .withLoading(isLoading: $viewModel.isLoading)
        .crossPlatformSheet(isPresented: $showAssetSelection) {
            AssetSelectionListScreen(
                isPresented: $showAssetSelection,
                selectedAsset: $viewModel.selectedAsset,
                dataSource: viewModel.assetsDataSource
            ) { showAssetSelection = false }
        }
    }
    
    func onContinue() {
        switch focusedFieldBinding {
        case .address:
            focusedFieldBinding =  .amount
        case .amount, nil:
            if viewModel.lpUnitsField.valid, !viewModel.addressViewModel.field.valid {
                focusedField = .address
                return
            }
            
            guard let transactionBuilder = viewModel.transactionBuilder else { return }
            onVerify(transactionBuilder)
        }
    }
    
    func onAddressFill() {
        focusedFieldBinding = viewModel.addressViewModel.field.valid ? .amount : .address
    }
}

#Preview {
    UnbondMayaTransactionScreen(
        viewModel: UnbondMayaTransactionViewModel(
            coin: .example,
            vault: .example,
            initialBondAddress: nil
        )
    ) { _ in }
}
