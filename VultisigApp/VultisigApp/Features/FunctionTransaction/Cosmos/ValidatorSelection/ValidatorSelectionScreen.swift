//
//  ValidatorSelectionScreen.swift
//  VultisigApp
//
//  Validator-picker sheet for the LUNA / LUNC delegate / redelegate flows.
//  Matches Figma `75918:74747` — `SearchTextField` + scrollable `LazyVStack`
//  of `ValidatorCard`s with the selected-state stroke variant.
//
//  Sheet-presented; tapping a row stages a local "picked" address (without
//  dismissing) and the footer confirm button commits the selection to the
//  parent's `selectedValidator` binding and dismisses the sheet. This
//  two-tap pattern matches the desktop client's `ValidatorPickerSheet`.
//

import SwiftUI

struct ValidatorSelectionScreen: View {
    @Binding var isPresented: Bool
    @Binding var selectedValidator: CosmosValidator?
    let chainTicker: String
    @StateObject var viewModel: ValidatorSelectionViewModel
    @State private var pickedAddress: String?

    init(
        isPresented: Binding<Bool>,
        selectedValidator: Binding<CosmosValidator?>,
        chain: Chain,
        chainTicker: String,
        excludedValidators: Set<String> = []
    ) {
        self._isPresented = isPresented
        self._selectedValidator = selectedValidator
        self.chainTicker = chainTicker
        self._viewModel = .init(wrappedValue: ValidatorSelectionViewModel(
            chain: chain,
            excludedValidators: excludedValidators
        ))
    }

    var body: some View {
        Screen {
            VStack(spacing: 8) {
                SearchTextField(value: $viewModel.searchText)
                ScrollView {
                    if viewModel.isLoading {
                        loadingView
                    } else if let error = viewModel.error {
                        ErrorMessage(text: error)
                            .padding(.top, 48)
                    } else if !viewModel.filteredValidators.isEmpty {
                        list
                    } else {
                        ErrorMessage(text: "cosmosStakingNoValidatorsFound")
                            .padding(.top, 48)
                    }
                }
                .cornerRadius(12)

                PrimaryButton(
                    title: "cosmosStakingSelectValidator".localized
                ) {
                    confirmSelection()
                }
                .disabled(pickedAddress == nil)
                .opacity(pickedAddress == nil ? 0.5 : 1)
                .padding(.top, 8)
            }
        }
        .screenTitle("cosmosStakingSelectValidator".localized)
        .screenBackButtonHidden()
        .screenToolbar {
            CustomToolbarItem(placement: .leading) {
                ToolbarButton(image: "x") {
                    isPresented.toggle()
                }
            }
        }
        .applySheetSize()
        .sheetStyle()
        .onDisappear { viewModel.searchText = "" }
        .onLoad {
            pickedAddress = selectedValidator?.operatorAddress
            Task { await viewModel.load() }
        }
    }

    private var list: some View {
        LazyVStack(spacing: 8) {
            ForEach(viewModel.filteredValidators, id: \.operatorAddress) { validator in
                ValidatorCard(
                    validator: validator,
                    chainTicker: chainTicker,
                    isSelected: pickedAddress == validator.operatorAddress
                ) {
                    pickedAddress = validator.operatorAddress
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func confirmSelection() {
        guard let pickedAddress,
              let validator = viewModel.filteredValidators.first(where: { $0.operatorAddress == pickedAddress })
        else { return }
        selectedValidator = validator
        isPresented = false
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            SpinningLineLoader()
                .scaleEffect(1.2)
            Text(NSLocalizedString("loading", comment: ""))
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 48)
    }
}
