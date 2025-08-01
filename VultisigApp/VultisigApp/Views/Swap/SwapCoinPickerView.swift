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
    let isLoading: Bool
    
    @State var searchText = ""
    @EnvironmentObject var viewModel: CoinSelectionViewModel
    
    private let balanceService = BalanceService.shared
    
    var header: some View {
        HStack {
            backButton
                .frame(maxWidth: .infinity, alignment: .leading)
            title
                .frame(maxWidth: .infinity, alignment: .center)
            Spacer()
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 16)
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
    
    var content: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 12) {
                    searchBar
                    
                    if isLoading {
                        loadingView
                    } else if getCoins().count > 0 {
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
                chainCarousel
            }
            .padding(.top, 4)
            .background(Color.backgroundBlue)
            .shadow(color: Color.backgroundBlue, radius: 15)
        }
    }
    
    var loadingView: some View {
        VStack(spacing: 16) {
            SpinningLineLoader()
                .scaleEffect(1.2)
            
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
    
    var searchBar: some View {
        SearchTextField(value: $searchText)
            .padding(.bottom, 12)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
    }
    
    let itemSize: CGFloat = 120
    var chainCarousel: some View {
        ZStack {
            Capsule()
                .fill(Color.blue600)
                .allowsHitTesting(false)
                .frame(width: itemSize)
                .shadow(color: .blue200, radius: 6)
            
            FlatPicker(selectedItem: $selectedChain, items: availableChains, itemSize: itemSize + 8, axis: .horizontal) { chain in
                let isSelected = selectedChain == chain
                Button {
                    selectedChain = chain
                } label: {
                    HStack(spacing: 4) {
                        Image(chain.logo)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 28)
                        Text(chain.name)
                            .font(.body12BrockmannMedium)
                            .foregroundColor(isSelected ? .neutral0 : .extraLightGray)
                    }
                    .padding(8)
                    .frame(width: itemSize)
                    .background(
                        Capsule()
                            .strokeBorder(Color.blue400, lineWidth: 1)
                            .fill(Color.blue600)
                    )
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                    .animation(.easeInOut, value: isSelected)
                }
            }
            
            Capsule()
                .strokeBorder(Color.persianBlue400, lineWidth: 2)
                .allowsHitTesting(false)
                .frame(width: itemSize)
        }
        .frame(height: 44)
    }
    
    private func getCoins() -> [Coin] {
        let availableCoins = vault.coins.filter { coin in
            coin.chain == selectedChain
        }
        
        // Filter by search text if not empty
        let filteredCoins = if searchText.isEmpty {
            availableCoins
        } else {
            availableCoins.filter { coin in
                coin.ticker.localizedCaseInsensitiveContains(searchText) ||
                coin.contractAddress.localizedCaseInsensitiveContains(searchText) ||
                coin.chain.name.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Sort coins: native token first, then by USD balance in descending order
        var sortedCoins = filteredCoins.sorted { first, second in
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
        
        if let indexOfSelected = sortedCoins.firstIndex(of: selectedCoin) {
            sortedCoins.remove(at: indexOfSelected)
            sortedCoins = [selectedCoin] + sortedCoins
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
    
    private func selectChain(_ chain: Chain) {
        selectedChain = chain
        
        // Select first coin of the chain automatically
        let availableCoins = getCoins()
        if let firstCoin = availableCoins.first {
            selectedCoin = firstCoin
        }
        
    }
    
    // Disabled along with custom token button
}

#Preview {
    SwapCoinPickerView(vault: Vault.example, showSheet: .constant(true), selectedCoin: .constant(Coin.example), selectedChain: .constant(Chain.example), isLoading: false)
}
