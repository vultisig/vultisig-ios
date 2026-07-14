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
    /// When `true`, expand the picker with SwapKit `/tokens` entries on top
    /// of the curated + 1inch + Jupiter lists, gated by the SwapKit feature
    /// flag. Source-side picker is `false` so its behaviour stays identical
    /// to Phase 1 (the user can only swap from coins they hold).
    let isDestination: Bool

    @StateObject var viewModel: SwapCoinSelectionViewModel
    @EnvironmentObject var coinSelectionViewModel: CoinSelectionViewModel
    @State var searchBarFocused: Bool = false
    @State private var reloadTask: Task<Void, Never>?

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
        selectedChain: Chain?,
        isDestination: Bool = false
    ) {
        self.vault = vault
        self._showSheet = showSheet
        self._selectedCoin = selectedCoin
        self.selectedChain = selectedChain
        self.isDestination = isDestination
        self._viewModel = StateObject(
            wrappedValue: .init(
                vault: vault,
                selectedCoin: selectedCoin.wrappedValue,
                isDestination: isDestination
            )
        )
    }

    var body: some View {
        content.sheetContainer()
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
            // First open per presentation forces a SwapKit catalog refresh so a
            // stale token list (or one that missed the cold-launch fetch) is
            // re-fetched. In-session chain re-selects stay on cached data.
            reloadCoins(forceRefresh: true)
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
                .foregroundStyle(Theme.colors.textTertiary)
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
                            .foregroundStyle(isSelected ? Theme.colors.textPrimary : Theme.colors.textTertiary)
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
            .filter { vault.availableChains.contains($0) }
    }

    private func reloadCoins(forceRefresh: Bool = false) {
        // Cancel any in-flight load so a fast chain-switch superseding a cold
        // fetch can't publish results for the wrong chain.
        reloadTask?.cancel()
        reloadTask = Task {
            // Debounce a burst of back-and-forth chain switches: the cancel
            // above coalesces the burst so only the last selection's task
            // survives the sleep and actually fetches. First open
            // (forceRefresh) skips the delay to stay snappy.
            if !forceRefresh {
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
            // Applies to both the debounced and the forced path: a task the
            // cancel above superseded must not go on to fetch/publish.
            guard !Task.isCancelled else { return }
            guard let selectedChain else { return }
            await viewModel.fetchCoins(chain: selectedChain, forceRefresh: forceRefresh)
        }
    }

    private func onSelect(chain: Chain) {
        // Only mutate the selection; the single `.onChange(of: selectedChain)`
        // owns the reload. Calling `reloadCoins()` here too fired two loads per
        // tap, doubling the merge+sort work during rapid chain switching.
        selectedChain = chain
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
        selectedChain: Chain.example,
        isDestination: false
    )
}
