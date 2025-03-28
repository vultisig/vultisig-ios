//
//  SwapNetworkPickerView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-03-26.
//

import SwiftUI

struct SwapNetworkPickerView: View {
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
            .filter { $0.name.lowercased().contains(searchText.lowercased()) }
    }

    var body: some View {
        content
    }
    
    var content: some View {
        ZStack {
            ZStack {
                Background()
                main
            }
        }
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
                    networkTitle
                    list
                } else {
                    emptyMessage
                }
            }
            .padding(.vertical, 8)
            .padding(.bottom, UIDevice.current.userInterfaceIdiom == .pad ? 50 : 0)
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
        VStack(spacing: 0) {
            ForEach(filteredChains, id: \.self) { chain in
                SwapNetworkCell(
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
        TextField(NSLocalizedString("Search", comment: "Search"), text: $searchText)
            .font(.body16Menlo)
            .foregroundColor(.neutral0)
            .disableAutocorrection(true)
            .padding(.horizontal, 8)
            .borderlessTextFieldStyle()
            .colorScheme(.dark)
    }
}

#Preview {
    SwapNetworkPickerView(
        vault: Vault.example,
        showSheet: .constant(true),
        selectedChain: .constant(Chain.example),
        selectedCoin: .constant(Coin.example)
    )
}
