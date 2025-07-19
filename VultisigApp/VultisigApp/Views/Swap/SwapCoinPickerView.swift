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
    @Binding var selectedChain: Chain?
    @EnvironmentObject var swapViewModel: SwapCryptoViewModel
    
    @State var searchText = ""
    @State var showChainPickerSheet: Bool = false
    @EnvironmentObject var viewModel: CoinSelectionViewModel
    
    var main: some View {
        VStack {
            header
            views
        }
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
        .padding(16)
    }
    
    var backButton: some View {
        Button {
            showSheet = false
        } label: {
            NavigationBlankBackButton()
        }
    }
    
    var title: some View {
        Text(NSLocalizedString("selectAsset", comment: ""))
            .foregroundColor(.neutral0)
            .font(.body18BrockmannMedium)
    }
    
    var view: some View {
        ScrollView {
            VStack(spacing: 12) {
                searchBar
                chainSelector
                
                if swapViewModel.isLoading {
                    loadingView
                } else if getCoins().count > 0 {
                    networkTitle
                    list
                } else {
                    emptyMessage
                }
                
                // Chain carousel at bottom
                chainCarousel
            }
            .padding(.vertical, 8)
            .padding(.bottom, 50)
            .padding(.horizontal, 16)
        }
    }
    
    var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
                .foregroundColor(.turquoise600)
            
            Text(NSLocalizedString("loading", comment: ""))
                .font(.body14BrockmannMedium)
                .foregroundColor(.extraLightGray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 48)
    }
    
    var networkTitle: some View {
        Text(NSLocalizedString("network", comment: ""))
            .font(.body12BrockmannMedium)
            .foregroundColor(.extraLightGray)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var list: some View {
        LazyVStack(spacing: 0) {
            ForEach(getCoins(), id: \.self) { coin in
                SwapCoinCell(
                    coin: coin,
                    selectedCoin: $selectedCoin,
                    showSheet: $showSheet
                )
            }
        }
        .cornerRadius(12)
    }
    
    var emptyMessage: some View {
        ErrorMessage(text: "noResultFound")
            .padding(.top, 48)
    }
    
    var views: some View {
        ZStack {
            Background()
            view
        }
    }

    var searchBar: some View {
        searchField
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .padding(.horizontal, 12)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .background(Color.blue600)
            .cornerRadius(12)
            .padding(.bottom, 12)
    }
    
    var chainSelector: some View {
        HStack(spacing: 6) {
            Text(NSLocalizedString("chain", comment: ""))
                .font(.body12BrockmannMedium)
                .foregroundColor(.extraLightGray)
            
            chainSelectorButton
            
            Spacer()
        }
    }
    
    var chainSelectorButton: some View {
        Button {
            showChainPickerSheet = true
        } label: {
            chainSelectorLabel
        }
    }
    
    var chainSelectorLabel: some View {
        HStack(spacing: 4) {
            Image(selectedChain?.logo ?? "")
                .resizable()
                .frame(width: 16, height: 16)
            
            Text(selectedChain?.name ?? "")
            
            Image(systemName: "chevron.down")
        }
        .foregroundColor(.neutral0)
        .font(.body12BrockmannMedium)
    }

    var searchField: some View {
        HStack(spacing: 0) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.extraLightGray)
            
            TextField(NSLocalizedString("Search", comment: "Search"), text: $searchText)
                .foregroundColor(.neutral0)
                .disableAutocorrection(true)
                .padding(.horizontal, 8)
                .borderlessTextFieldStyle()
                .colorScheme(.dark)
        }
        .font(.body16Menlo)
    }
    
    var chainCarousel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("selectChain", comment: ""))
                .font(.body14BrockmannMedium)
                .foregroundColor(.neutral0)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(availableChains, id: \.self) { chain in
                        Button {
                            selectedChain = chain
                        } label: {
                            HStack(spacing: 6) {
                                Image(chain.logo)
                                    .resizable()
                                    .frame(width: 16, height: 16)
                                
                                Text(chain.name)
                                    .font(.body12BrockmannMedium)
                                    .foregroundColor(selectedChain == chain ? .neutral0 : .extraLightGray)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selectedChain == chain ? Color.blue600 : Color.clear)
                            )
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
    
    private func getCoins() -> [Coin] {
        let availableCoins = vault.coins.filter { coin in
            coin.chain == selectedChain
        }
        
        // Sort coins: native token first, then by USD balance in descending order
        let sortedCoins = availableCoins.sorted { first, second in
            // Native token always comes first
            if first.isNativeToken && !second.isNativeToken {
                return true
            }
            if !first.isNativeToken && second.isNativeToken {
                return false
            }
            
            // If both are native or both are not native, sort by USD balance
            return first.balanceInFiatDecimal > second.balanceInFiatDecimal
        }
        
        return sortedCoins
    }
    
    private var availableChains: [Chain] {
        let chains = vault.coins.map { coin in
            coin.chain
        }
        return Array(Set(chains)).sorted {
            $0.name < $1.name
        }
    }
}

#Preview {
    SwapCoinPickerView(vault: Vault.example, showSheet: .constant(true), selectedCoin: .constant(Coin.example), selectedChain: .constant(Chain.example))
}
