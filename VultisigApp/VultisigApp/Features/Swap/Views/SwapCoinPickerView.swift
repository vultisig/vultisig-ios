//
//  SwapCoinPickerView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-03-27.
//

import SwiftUI

struct SwapCoinPickerView: View {
    let vault: Vault
    @Binding var showSheet: Bool
    @Binding var selectedCoin: Coin
    @State var selectedChain: Chain?

    @StateObject var viewModel: SwapCoinSelectionViewModel
    @EnvironmentObject var coinSelectionViewModel: CoinSelectionViewModel
    @State var searchBarFocused: Bool = false

    var showSelectChainHeader: Bool {
        #if os(macOS)
        return true
        #else
        return !searchBarFocused
        #endif
    }

    init(
        vault: Vault,
        showSheet: Binding<Bool>,
        selectedCoin: Binding<Coin>,
        selectedChain: Chain?
    ) {
        self.vault = vault
        self._showSheet = showSheet
        self._selectedCoin = selectedCoin
        self.selectedChain = selectedChain
        self._viewModel = StateObject(wrappedValue: .init(vault: vault, selectedCoin: selectedCoin.wrappedValue))
    }

    var body: some View {
        container
    }

    var container: some View {
#if os(iOS)
        NavigationStack {
            content
        }
#else
        content
            .presentationSizingFitted()
            .applySheetSize()
            .transaction { $0.disablesAnimations = true }
#endif
    }

    var content: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 12) {
                searchBar
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        if viewModel.isLoading {
                            loadingView
                        } else if !viewModel.filteredTokens.isEmpty {
                            list
                        } else {
                            emptyMessage
                        }
                    }
                    .padding(.bottom, 80)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)

            VStack(spacing: 12) {
                GradientListSeparator()
                Text("selectChain".localized)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .showIf(showSelectChainHeader)
                    .animation(.easeInOut.delay(0.4), value: showSelectChainHeader)
                chainCarousel
            }
            .padding(.vertical, 4)
            .background(Theme.colors.bgPrimary)
            .shadow(color: Theme.colors.bgPrimary, radius: 15)
        }
        .onLoad {
            viewModel.setup()
            reloadCoins()
        }
        .onChange(of: selectedChain) { _, _ in
            reloadCoins()
        }
        .crossPlatformToolbar(showsBackButton: false) {
            CustomToolbarItem(placement: .leading) {
                ToolbarButton(image: "x") {
                    showSheet.toggle()
                }
            }
        }
        .background(Theme.colors.bgPrimary)
        .applySheetSize()
        .sheetStyle()
    }

    var loadingView: some View {
        VStack(spacing: 16) {
            SpinningLineLoader()
                .scaleEffect(1.2)

            Text(NSLocalizedString("loading", comment: ""))
                .font(Theme.fonts.bodySMedium)
                .foregroundColor(Theme.colors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 48)
    }

    @ViewBuilder
    var list: some View {
        LazyVStack(spacing: 0) {
            ForEach(viewModel.filteredTokens, id: \.self) { coinMeta in
                let vaultCoin = vault.coin(for: coinMeta)
                SwapCoinCell(
                    coin: coinMeta,
                    balance: vaultCoin?.balanceString,
                    balanceFiat: vaultCoin?.balanceInFiat,
                    isSelected: selectedCoin.toCoinMeta() == coinMeta
                ) {
                    onSelect(coin: coinMeta)
                }
            }
        }
        .cornerRadius(12)
    }

    var emptyMessage: some View {
        ErrorMessage(text: "noResultFound")
            .padding(.top, 48)
    }

    var searchBar: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("selectAsset".localized)
                .foregroundStyle(Theme.colors.textPrimary)
                .font(Theme.fonts.title2)
                .multilineTextAlignment(.leading)

            HStack(spacing: 12) {
                SearchTextField(value: $viewModel.searchText, isFocused: $searchBarFocused)
                Button {
                    viewModel.searchText = ""
                    searchBarFocused.toggle()
                } label: {
                    Text("cancel".localized)
                        .foregroundStyle(Theme.colors.textPrimary)
                        .font(Theme.fonts.bodySMedium)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
                .showIf(searchBarFocused)
            }
            .animation(.easeInOut, value: searchBarFocused)
        }
    }

    let itemSize: CGFloat = 120
    let itemPadding: CGFloat = 8
    var chainCarousel: some View {
        ZStack {
            Capsule()
                .fill(Theme.colors.bgPrimary)
                .allowsHitTesting(false)
                .frame(width: itemSize)
                .shadow(color: Theme.colors.border, radius: 6)

            let itemContainerSize = itemSize + itemPadding
            FlatPicker(selectedItem: $selectedChain, items: availableChains, itemSize: itemContainerSize, axis: .horizontal) { chain in
                let isSelected = selectedChain == chain
                Button {
                    onSelect(chain: chain)
                } label: {
                    HStack(spacing: 4) {
                        Image(chain.logo)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 28)
                        Text(chain.name)
                            .font(Theme.fonts.caption12)
                            .foregroundColor(isSelected ? Theme.colors.textPrimary : Theme.colors.textTertiary)
                            .fixedSize(horizontal: true, vertical: false)
                            .minimumScaleFactor(0.5)
                    }
                    .padding(itemPadding)
                    .frame(width: itemSize)
                    .background(
                        Capsule()
                            .strokeBorder(Theme.colors.bgSurface2, lineWidth: 1)
                            .fill(Theme.colors.bgPrimary)
                    )
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                    .animation(.easeInOut, value: isSelected)
                }
                .frame(width: itemContainerSize)
                .buttonStyle(.plain)
            }

            Capsule()
                .strokeBorder(Theme.colors.primaryAccent3, lineWidth: 2)
                .allowsHitTesting(false)
                .frame(width: itemSize)
        }
        .frame(height: 44)
    }

    private var availableChains: [Chain] {
        return coinSelectionViewModel.chains
            .filter(\.isSwapAvailable)
            .filter { vault.chains.contains($0) }
    }

    private func reloadCoins() {
        Task {
            guard let selectedChain else { return }
            await viewModel.fetchCoins(chain: selectedChain)
        }
    }

    private func onSelect(chain: Chain) {
        selectedChain = chain
        reloadCoins()
    }

    private func onSelect(coin: CoinMeta) {
        guard let newCoin = viewModel.onSelect(coin: coin) else {
            return
        }
        selectedCoin = newCoin
        showSheet = false
    }
}

#Preview {
    SwapCoinPickerView(
        vault: Vault.example,
        showSheet: .constant(true),
        selectedCoin: .constant(Coin.example),
        selectedChain: Chain.example
    )
}
