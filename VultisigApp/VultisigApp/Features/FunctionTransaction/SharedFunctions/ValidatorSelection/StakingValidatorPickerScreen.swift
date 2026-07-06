//
//  StakingValidatorPickerScreen.swift
//  VultisigApp
//
//  Shared validator-picker sheet for the Cosmos + Solana staking flows. Generic
//  over the chain's validator type and fed by a `StakingValidatorSource`.
//  `SearchTextField` + scrollable `LazyVStack` of `StakingValidatorCard`s with
//  the selected-state stroke variant.
//
//  Tapping a row highlights it, then after a short delay commits the selection
//  to the parent's binding and dismisses the sheet — the delay lets the user see
//  the row selected before the sheet closes.
//

import SwiftUI

struct StakingValidatorPickerScreen<V: StakingValidatorConvertible>: View {
    @Binding var isPresented: Bool
    @Binding var selectedValidator: V?
    let chainTicker: String
    let chainDecimals: Int
    @StateObject private var viewModel: StakingValidatorPickerViewModel<V>
    /// The highlighted row's id. Set immediately on tap so the selection is
    /// visible during the brief delay before the sheet dismisses.
    @State private var pickedID: String?
    /// Drives the select-then-dismiss delay; cancelled if the user taps again or
    /// closes the sheet before it fires.
    @State private var selectionTask: Task<Void, Never>?

    init(
        isPresented: Binding<Bool>,
        selectedValidator: Binding<V?>,
        source: StakingValidatorSource<V>,
        chainTicker: String,
        chainDecimals: Int
    ) {
        self._isPresented = isPresented
        self._selectedValidator = selectedValidator
        self.chainTicker = chainTicker
        self.chainDecimals = chainDecimals
        self._viewModel = .init(wrappedValue: StakingValidatorPickerViewModel(source: source))
    }

    var body: some View {
        content.sheetContainer()
    }

    private var content: some View {
        Screen {
            VStack(spacing: 8) {
                SearchTextField(value: $viewModel.searchText)
                columnHeader
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
        }
        .sheetStyle()
        .onDisappear {
            viewModel.searchText = ""
            selectionTask?.cancel()
        }
        .onLoad {
            pickedID = selectedValidator?.id
            Task { await viewModel.load() }
        }
    }

    private var columnHeader: some View {
        HStack {
            Text("cosmosStakingValidatorPicker".localized)
            Spacer()
            Text("cosmosStakingValidatorCommission".localized)
        }
        .font(Theme.fonts.caption12)
        .foregroundStyle(Theme.colors.textTertiary)
        .padding(.horizontal, 14)
    }

    private var list: some View {
        LazyVStack(spacing: 8) {
            ForEach(viewModel.filteredValidators) { validator in
                StakingValidatorCard(
                    validator: validator.makeStakingValidator(
                        ticker: chainTicker,
                        decimals: chainDecimals
                    ),
                    isSelected: pickedID == validator.id
                ) {
                    select(validator)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func select(_ validator: V) {
        pickedID = validator.id
        selectionTask?.cancel()
        selectionTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            selectedValidator = validator
            isPresented = false
        }
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
