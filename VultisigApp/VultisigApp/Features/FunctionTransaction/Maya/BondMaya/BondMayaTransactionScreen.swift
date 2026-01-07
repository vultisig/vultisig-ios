//
//  BondMayaTransactionScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/11/2025.
//

import SwiftUI

struct BondMayaTransactionScreen: View {
    enum FocusedField {
        case address, amount
    }
    
    @StateObject var viewModel: BondMayaTransactionViewModel
    var onVerify: (TransactionBuilder) -> Void
    
    @State var focusedFieldBinding: FocusedField? = .none
    @FocusState private var focusedField: FocusedField?
    
    @State var showAssetSelection: Bool = false
    
    var body: some View {
        FormScreen(
            title: "bond".localized,
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

                    // Available LP units display
                    if let availableUnits = viewModel.availableLPUnits {
                        HStack {
                            Text("availableLPUnits".localized)
                                .font(Theme.fonts.caption12)
                                .foregroundColor(Theme.colors.textTertiary)
                            Spacer()
                            Text(availableUnits)
                                .font(Theme.fonts.caption12)
                                .foregroundColor(Theme.colors.textPrimary)
                        }
                    }

                    // Minimum LP units suggestion
                    if let minUnits = viewModel.minimumLPUnitsNeeded {
                        HStack {
                            Text("minimumLPUnitsNeeded".localized)
                                .font(Theme.fonts.caption12)
                                .foregroundColor(Theme.colors.textTertiary)
                            Spacer()
                            Text("\(minUnits)")
                                .font(Theme.fonts.caption12)
                                .foregroundColor(Theme.colors.alertWarning)
                            Button(action: {
                                viewModel.lpUnitsField.value = "\(minUnits)"
                            }) {
                                Text("use".localized)
                                    .font(Theme.fonts.caption12)
                                    .foregroundColor(Theme.colors.alertInfo)
                            }
                        }
                    }

                    // Estimated CACAO value
                    if let cacaoValue = viewModel.estimatedCacaoValue {
                        HStack {
                            Text("estimatedBondValue".localized)
                                .font(Theme.fonts.caption12)
                                .foregroundColor(Theme.colors.textTertiary)
                            Spacer()
                            Text("\(cacaoValue.formatted()) CACAO")
                                .font(Theme.fonts.caption12)
                                .foregroundColor(
                                    cacaoValue >= viewModel.minimumBondRequired
                                        ? Theme.colors.alertSuccess
                                        : Theme.colors.alertWarning
                                )
                        }
                    }

                    // Minimum requirement display
                    HStack {
                        Text("minimumBondRequired".localized)
                            .font(Theme.fonts.caption12)
                            .foregroundColor(Theme.colors.textTertiary)
                        Spacer()
                        Text("\(viewModel.minimumBondRequired.formatted()) CACAO")
                            .font(Theme.fonts.caption12)
                            .foregroundColor(Theme.colors.textTertiary)
                    }

                    // HARD VALIDATION ERROR (blocks transaction)
                    if let error = viewModel.bondValidationError {
                        HStack(spacing: 8) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(Theme.colors.alertError)
                            Text(error)
                                .font(Theme.fonts.caption12)
                                .foregroundColor(Theme.colors.textPrimary)
                            Spacer()
                        }
                        .padding(12)
                        .background(Theme.colors.bgError)
                        .cornerRadius(8)
                    }

                    // SOFT VALIDATION WARNING (doesn't block)
                    if let warning = viewModel.bondValidationWarning {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(Theme.colors.alertWarning)
                            Text(warning)
                                .font(Theme.fonts.caption12)
                                .foregroundColor(Theme.colors.textPrimary)
                            Spacer()
                        }
                        .padding(12)
                        .background(Theme.colors.bgAlert)
                        .cornerRadius(8)
                    }
                }
            }
        }
        .onLoad {
            viewModel.onLoad()
            onAddressFill()
        }
        .onChange(of: viewModel.addressViewModel.field.valid) { _, isValid in
            onAddressFill()
        }
        .onChange(of: focusedFieldBinding) { oldValue, newValue in
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
    BondMayaTransactionScreen(
        viewModel: BondMayaTransactionViewModel(
            coin: .example,
            vault: .example,
            initialBondAddress: nil
        )
    ) { _ in }
}
