//
//  ValidatorSelectionScreen.swift
//  VultisigApp
//
//  Validator-picker sheet for the LUNA / LUNC delegate / redelegate flows.
//  `SearchTextField` + scrollable `LazyVStack` of `ValidatorCard`s with the
//  selected-state stroke variant.
//
//  Sheet-presented; tapping a row stages a local "picked" address (without
//  dismissing) and the trailing toolbar confirm button commits the
//  selection to the parent's `selectedValidator` binding and dismisses the
//  sheet. This two-tap pattern matches the desktop client's
//  `ValidatorPickerSheet`.
//

import SwiftUI

struct ValidatorSelectionScreen: View {
    @Binding var isPresented: Bool
    @Binding var selectedValidator: CosmosValidator?
    let chainTicker: String
    @StateObject private var viewModel: ValidatorSelectionViewModel
    /// Persist the entire picked validator (not just the address). Resolving
    /// against `filteredValidators` at confirm time would silently no-op if
    /// the user typed a search term that filters the picked row out.
    @State private var pickedValidator: CosmosValidator?

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
                        ErrorMessage(text: "cosmosStakingNoValidatorsFound".localized)
                            .padding(.top, 48)
                    }
                }
                .cornerRadius(12)
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
            CustomToolbarItem(placement: .trailing) {
                ToolbarButton(image: "check") {
                    confirmSelection()
                }
                .disabled(pickedValidator == nil)
                .opacity(pickedValidator == nil ? 0.5 : 1)
            }
        }
        .applySheetSize()
        .sheetStyle()
        .onDisappear { viewModel.searchText = "" }
        .onLoad {
            pickedValidator = selectedValidator
            Task { await viewModel.load() }
        }
    }

    private var list: some View {
        LazyVStack(spacing: 8) {
            ForEach(viewModel.filteredValidators, id: \.operatorAddress) { validator in
                ValidatorCard(
                    validator: validator,
                    chainTicker: chainTicker,
                    isSelected: pickedValidator?.operatorAddress == validator.operatorAddress
                ) {
                    pickedValidator = validator
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func confirmSelection() {
        guard let pickedValidator else { return }
        selectedValidator = pickedValidator
        isPresented = false
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            SpinningLineLoader()
                .scaleEffect(1.2)
            Text("loading".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 48)
    }
}
