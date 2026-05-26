//
//  ValidatorSelectionScreen.swift
//  VultisigApp
//
//  Validator-picker sheet for the LUNA / LUNC delegate / redelegate flows.
//  Matches Figma `75918:74747` — `SearchTextField` + scrollable `LazyVStack`
//  of `ValidatorCard`s with the selected-state stroke variant.
//
//  Sheet-presented; on tap the screen sets the parent's `selectedValidator`
//  binding and dismisses itself via `isPresented`.
//

import SwiftUI

struct ValidatorSelectionScreen: View {
    @Binding var isPresented: Bool
    @Binding var selectedValidator: CosmosValidator?
    let chainTicker: String
    @StateObject var viewModel: ValidatorSelectionViewModel

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
            Task { await viewModel.load() }
        }
    }

    private var list: some View {
        LazyVStack(spacing: 8) {
            ForEach(viewModel.filteredValidators, id: \.operatorAddress) { validator in
                ValidatorCard(
                    validator: validator,
                    chainTicker: chainTicker,
                    isSelected: selectedValidator?.operatorAddress == validator.operatorAddress
                ) {
                    selectedValidator = validator
                    isPresented = false
                }
            }
        }
        .padding(.vertical, 4)
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
