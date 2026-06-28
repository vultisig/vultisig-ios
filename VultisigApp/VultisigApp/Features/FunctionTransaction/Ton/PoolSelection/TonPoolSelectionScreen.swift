//
//  TonPoolSelectionScreen.swift
//  VultisigApp
//
//  Staking-pool picker sheet for the TON first-time-stake flow. `SearchTextField`
//  + scrollable `LazyVStack` of `TonPoolCard`s with the selected-state stroke
//  variant. Tapping a row highlights it, then after a short delay commits the
//  selection to the parent's `selectedPool` binding and dismisses. Mirrors
//  `ValidatorSelectionScreen`.
//

import SwiftUI

struct TonPoolSelectionScreen: View {
    @Binding var isPresented: Bool
    @Binding var selectedPool: TonStakingPool?
    let ticker: String
    @StateObject private var viewModel: TonPoolSelectionViewModel
    /// The highlighted row. Set immediately on tap so the selection is visible
    /// during the brief delay before the sheet dismisses.
    @State private var pickedPool: TonStakingPool?
    /// Drives the select-then-dismiss delay; cancelled if the user taps again
    /// or closes the sheet before it fires.
    @State private var selectionTask: Task<Void, Never>?

    init(
        isPresented: Binding<Bool>,
        selectedPool: Binding<TonStakingPool?>,
        ticker: String,
        decimals: Int
    ) {
        self._isPresented = isPresented
        self._selectedPool = selectedPool
        self.ticker = ticker
        self._viewModel = .init(wrappedValue: TonPoolSelectionViewModel(decimals: decimals))
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
                    } else if !viewModel.filteredPools.isEmpty {
                        list
                    } else {
                        ErrorMessage(text: "tonStakingNoPoolsFound".localized)
                            .padding(.top, 48)
                    }
                }
                .cornerRadius(12)
            }
        }
        .screenTitle("tonStakingSelectPool".localized)
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
            pickedPool = selectedPool
            Task { await viewModel.load() }
        }
    }

    private var columnHeader: some View {
        HStack {
            Text("tonStakingPoolPicker".localized)
            Spacer()
            Text("tonStakingAPY".localized)
        }
        .font(Theme.fonts.caption12)
        .foregroundStyle(Theme.colors.textTertiary)
        .padding(.horizontal, 14)
    }

    private var list: some View {
        LazyVStack(spacing: 8) {
            ForEach(viewModel.filteredPools, id: \.address) { pool in
                TonPoolCard(
                    pool: pool,
                    ticker: ticker,
                    isSelected: pickedPool?.address == pool.address
                ) {
                    select(pool)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func select(_ pool: TonStakingPool) {
        pickedPool = pool
        selectionTask?.cancel()
        selectionTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            selectedPool = pool
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
