//
//  SwapChainPickerView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-03-26.
//

import SwiftUI

struct SwapChainPickerView: View {
    let vault: Vault
    @Binding var showSheet: Bool
    @Binding var selectedChain: Chain?
    @Binding var selectedCoin: Coin

    @State var searchText = ""
    @State var isLoadingBalances: Bool = false
    @State var balanceUpdateId = UUID()
    @EnvironmentObject var viewModel: CoinSelectionViewModel
    
    private let balanceService = BalanceService.shared
    
    var filteredChains: [Chain] {
        let chains = vault.coins.map { coin in
            coin.chain
        }
        
        let chainsArray = Array(Set(chains)).sorted {
            $0.name < $1.name
        }
        
        return searchText.isEmpty
            ? chainsArray
            : chainsArray
            .filter { chain in
                // Search by chain name
                chain.name.lowercased().contains(searchText.lowercased()) ||
                // Search by native token ticker
                chain.ticker.lowercased().contains(searchText.lowercased())
            }
    }
    
    var content: some View {
        ZStack {
            ZStack {
                Background()
                main
            }
        }
        .buttonStyle(BorderlessButtonStyle())
    }
    
    var main: some View {
        VStack {
            header
            views
        }
        .task {
            await loadAllBalances()
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
        Text(NSLocalizedString("selectNetwork", comment: ""))
            .foregroundColor(.neutral0)
            .font(.body18BrockmannMedium)
    }
    
    var view: some View {
        ScrollView {
            VStack(spacing: 12) {
                searchBar
                
                if isLoadingBalances {
                    loadingView
                } else if filteredChains.count > 0 {
                    networkTitle
                    list
                } else {
                    emptyMessage
                }
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
            ForEach(filteredChains, id: \.self) { chain in
                SwapChainCell(
                    coins: vault.coins,
                    chain: chain,
                    selectedCoin: $selectedCoin,
                    selectedChain: $selectedChain,
                    showSheet: $showSheet
                )
            }
        }
        .cornerRadius(12)
        .id(balanceUpdateId)
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

    var searchField: some View {
        HStack(spacing: 0) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.extraLightGray)
            
            TextField(NSLocalizedString("Search", comment: "Search"), text: $searchText)
                .font(.body16Menlo)
                .foregroundColor(.neutral0)
                .disableAutocorrection(true)
                .borderlessTextFieldStyle()
                .colorScheme(.dark)
                .padding(.horizontal, 8)
        }
    }
    
    private func loadAllBalances() async {
        await MainActor.run {
            isLoadingBalances = true
        }
        
        // Load balances for all coins in the vault
        await withTaskGroup(of: Void.self) { group in
            for coin in vault.coins {
                group.addTask {
                    await viewModel.loadData(coin: coin)
                }
            }
        }
        
        // Small delay to ensure data is propagated
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
        
        await MainActor.run {
            isLoadingBalances = false
            // Force view refresh by updating the ID
            balanceUpdateId = UUID()
        }
    }
}

#Preview {
    SwapChainPickerView(
        vault: Vault.example,
        showSheet: .constant(true),
        selectedChain: .constant(Chain.example),
        selectedCoin: .constant(Coin.example)
    )
}
