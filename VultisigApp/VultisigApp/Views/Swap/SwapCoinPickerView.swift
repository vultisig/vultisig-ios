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
    
    var header: some View {
        HStack {
            backButton
            Spacer()
            title
            Spacer()
            backButton
                .opacity(0)
        }
    }
    
    @ViewBuilder
    var backButton: some View {
        #if os(macOS)
            Button {
                showSheet = false
            } label: {
                NavigationBlankBackButton()
            }
        #endif
    }
    
    var title: some View {
        Text(NSLocalizedString("selectAsset", comment: ""))
            .foregroundColor(Theme.colors.textPrimary)
            .font(Theme.fonts.bodyLMedium)
    }
    
    var content: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 12) {
                    searchBar
                    
                    if viewModel.isLoading {
                        loadingView
                    } else if !viewModel.filteredTokens.isEmpty {
                        networkTitle
                        list
                    } else {
                        emptyMessage
                    }
                }
                .padding(.vertical, 8)
                .padding(.bottom, 50)
            }
            
            VStack(spacing: 12) {
                GradientListSeparator()
                Text("selectChain".localized)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textExtraLight)
                chainCarousel
            }
            .padding(.top, 4)
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
    }
    
    var loadingView: some View {
        VStack(spacing: 16) {
            SpinningLineLoader()
                .scaleEffect(1.2)
            
            Text(NSLocalizedString("loading", comment: ""))
                .font(Theme.fonts.bodySMedium)
                .foregroundColor(Theme.colors.textExtraLight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 48)
    }
    
    var networkTitle: some View {
        Text(NSLocalizedString("network", comment: ""))
            .font(Theme.fonts.caption12)
            .foregroundColor(Theme.colors.textExtraLight)
            .frame(maxWidth: .infinity, alignment: .leading)
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
        SearchTextField(value: $viewModel.searchText)
            .padding(.bottom, 12)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
    }
    
    let itemSize: CGFloat = 120
    var chainCarousel: some View {
        ZStack {
            Capsule()
                .fill(Theme.colors.bgPrimary)
                .allowsHitTesting(false)
                .frame(width: itemSize)
                .shadow(color: Theme.colors.border, radius: 6)
            
            FlatPicker(selectedItem: $selectedChain, items: availableChains, itemSize: itemSize + 8, axis: .horizontal) { chain in
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
                            .foregroundColor(isSelected ? Theme.colors.textPrimary : Theme.colors.textExtraLight)
                    }
                    .padding(8)
                    .frame(width: itemSize)
                    .background(
                        Capsule()
                            .strokeBorder(Theme.colors.bgTertiary, lineWidth: 1)
                            .fill(Theme.colors.bgPrimary)
                    )
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                    .animation(.easeInOut, value: isSelected)
                }
            }
            
            Capsule()
                .strokeBorder(Theme.colors.primaryAccent3, lineWidth: 2)
                .allowsHitTesting(false)
                .frame(width: itemSize)
        }
        .frame(height: 44)
    }
    
    private var availableChains: [Chain] {
        return coinSelectionViewModel.chains.filter(\.isSwapAvailable)
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
            guard let newCoin =  viewModel.onSelect(coin: coin) else {
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
