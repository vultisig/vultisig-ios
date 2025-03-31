//
//  SwapCoinPickerView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-03-27.
//

import SwiftUI

struct SwapCoinPickerView: View {
    let vault: Vault
    let selectedNetwork: Chain?
    @Binding var showSheet: Bool
    @Binding var selectedCoin: Coin
    @Binding var selectedChain: Chain?

    @State var searchText = ""
    @State var showChainPickerSheet: Bool = false
    @EnvironmentObject var viewModel: CoinSelectionViewModel

    var body: some View {
        content
            .sheet(isPresented: $showChainPickerSheet, content: {
                SwapChainPickerView(
                    vault: vault,
                    showSheet: $showChainPickerSheet,
                    selectedChain: $selectedChain,
                    selectedCoin: $selectedCoin
                )
            })
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
                
                if getCoins().count > 0 {
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
            Image(selectedNetwork?.logo ?? "")
                .resizable()
                .frame(width: 16, height: 16)
            
            Text(selectedNetwork?.name ?? "")
            
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
    
    private func getCoins() -> [Coin] {
        let availableCoins = vault.coins.filter { coin in
            coin.chain == selectedNetwork
        }.sorted {
            $0.ticker < $1.ticker
        }
        
        return searchText.isEmpty
            ? availableCoins
            : availableCoins
            .filter { $0.ticker.lowercased().contains(searchText.lowercased()) }
    }
}

#Preview {
    SwapCoinPickerView(vault: Vault.example, selectedNetwork: Chain.example, showSheet: .constant(true), selectedCoin: .constant(Coin.example), selectedChain: .constant(Chain.example))
}
