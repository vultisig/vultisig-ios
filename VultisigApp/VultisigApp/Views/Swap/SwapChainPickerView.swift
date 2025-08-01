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
    @EnvironmentObject var viewModel: CoinSelectionViewModel
    
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
                
                if filteredChains.count > 0 {
                    listHeader
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
    
    var listHeader: some View {
        HStack {
            Text(NSLocalizedString("chain", comment: ""))
                .font(.body12BrockmannMedium)
                .foregroundColor(.extraLightGray)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
            Text(NSLocalizedString("balance", comment: ""))
                .font(.body12BrockmannMedium)
                .foregroundColor(.extraLightGray)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 24)
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
        SearchTextField(value: $searchText)
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
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
