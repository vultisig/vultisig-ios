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
    @State var showChainPickerSheet: Bool = false
    @State var isLoadingBalances: Bool = false
    @EnvironmentObject var viewModel: CoinSelectionViewModel
    
    private let balanceService = BalanceService.shared
    
    var main: some View {
        VStack {
            header
            views
        }
        .task {
            if let selectedChain {
                await loadBalances()
            }
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
                
                if isLoading || isLoadingBalances {
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
            HStack(spacing: 6) {
                if let selectedChain {
                    Image(selectedChain.logo)
                        .resizable()
                        .frame(width: 16, height: 16)
                    
                    Text(selectedChain.name)
                        .font(.body14BrockmannMedium)
                        .foregroundColor(.neutral0)
                } else {
                    Text(NSLocalizedString("allChains", comment: ""))
                        .font(.body14BrockmannMedium)
                        .foregroundColor(.neutral0)
                }
                
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundColor(.extraLightGray)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.blue600)
            .cornerRadius(8)
        }
        .sheet(isPresented: $showChainPickerSheet) {
            SwapChainPickerView(
                vault: vault,
                showSheet: $showChainPickerSheet,
                selectedChain: $selectedChain,
                selectedCoin: $selectedCoin
            )
            .environmentObject(viewModel)
        }
        .onChange(of: selectedChain) { oldValue, newValue in
            if oldValue != newValue && newValue != nil {
                Task {
                    await loadBalances()
                }
            }
        }
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(availableChains, id: \.self) { chain in
                    Button {
                        selectChain(chain)
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
                        .background(selectedChain == chain ? Color.turquoise600 : Color.blue600)
                        .cornerRadius(20)
                    }
                }
            }
            .padding(.horizontal, 4)
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
        let sortedCoins = filteredCoins.sorted { first, second in
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
    
    private func selectChain(_ chain: Chain) {
        selectedChain = chain
        
        // Select first coin of the chain automatically
        let availableCoins = getCoins()
        if let firstCoin = availableCoins.first {
            selectedCoin = firstCoin
        }
        
        // Load balances for the selected chain
        Task {
            await loadBalances()
        }
    }
    
    private func loadBalances() async {
        await MainActor.run {
            isLoadingBalances = true
        }
        
        let chainCoins = vault.coins.filter { $0.chain == selectedChain }
        
        await withTaskGroup(of: Void.self) { group in
            for coin in chainCoins {
                group.addTask {
                    await viewModel.loadData(coin: coin)
                }
            }
        }
        
        await MainActor.run {
            isLoadingBalances = false
        }
    }
    
    // Disabled along with custom token button
}

#Preview {
    SwapCoinPickerView(vault: Vault.example, showSheet: .constant(true), selectedCoin: .constant(Coin.example), selectedChain: .constant(Chain.example), isLoading: false)
}
