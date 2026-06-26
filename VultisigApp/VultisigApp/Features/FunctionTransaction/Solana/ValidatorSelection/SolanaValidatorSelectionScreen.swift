//
//  SolanaValidatorSelectionScreen.swift
//  VultisigApp
//
//  Validator-picker sheet for the Solana delegate flow. `SearchTextField` +
//  scrollable `LazyVStack` of `SolanaValidatorCard`s with the selected-state
//  stroke variant. Mirrors the Cosmos `ValidatorSelectionScreen` — tapping a
//  row highlights it, then after a short delay commits the selection to the
//  parent's binding and dismisses the sheet.
//

import SwiftUI

struct SolanaValidatorSelectionScreen: View {
    @Binding var isPresented: Bool
    @Binding var selectedValidator: SolanaValidator?
    let chainTicker: String
    let chainDecimals: Int
    @StateObject private var viewModel: SolanaValidatorSelectionViewModel
    /// The highlighted row. Set immediately on tap so the selection is visible
    /// during the brief delay before the sheet dismisses.
    @State private var pickedValidator: SolanaValidator?
    /// Drives the select-then-dismiss delay; cancelled if the user taps again
    /// or closes the sheet before it fires.
    @State private var selectionTask: Task<Void, Never>?

    init(
        isPresented: Binding<Bool>,
        selectedValidator: Binding<SolanaValidator?>,
        chainTicker: String,
        chainDecimals: Int
    ) {
        self._isPresented = isPresented
        self._selectedValidator = selectedValidator
        self.chainTicker = chainTicker
        self.chainDecimals = chainDecimals
        self._viewModel = .init(wrappedValue: SolanaValidatorSelectionViewModel())
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
            pickedValidator = selectedValidator
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
            ForEach(viewModel.filteredValidators, id: \.votePubkey) { validator in
                SolanaValidatorCard(
                    validator: validator,
                    chainTicker: chainTicker,
                    chainDecimals: chainDecimals,
                    isSelected: pickedValidator?.votePubkey == validator.votePubkey
                ) {
                    select(validator)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func select(_ validator: SolanaValidator) {
        pickedValidator = validator
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
