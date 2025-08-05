//
//  SwapChainPickerView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-03-26.
//

import SwiftUI

struct SwapChainPickerView: View {
    enum FilterType {
        case swap
        case send
    }
    
    let filterType: FilterType
    let vault: Vault
    @Binding var showSheet: Bool
    @Binding var selectedChain: Chain?

    @State var searchText = ""
    @EnvironmentObject var viewModel: CoinSelectionViewModel
    
    init(
        filterType: FilterType = .send,
        vault: Vault,
        showSheet: Binding<Bool>,
        selectedChain: Binding<Chain?>
    ) {
        self.filterType = filterType
        self.vault = vault
        self._showSheet = showSheet
        self._selectedChain = selectedChain
    }
    
    var content: some View {
        ZStack {
            Background()
            main
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
                
                if viewModel.filteredChains.count > 0 {
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
            ForEach(sortedChains, id: \.chain) { (chain, balance) in
                SwapChainCell(
                    vault: vault,
                    chain: chain,
                    balance: balance,
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
            .padding(.bottom, 12)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
    }
    
    var sortedChains: [(chain: Chain, balance: String)] {
        filteredChains.map { chain in
            let totalFiat = vault.coins
                .filter { $0.chain == chain }
                .reduce(Decimal.zero) { sum, coin in
                    sum + coin.balanceInFiatDecimal
                }
            return (chain, totalFiat)
        }
        .sorted(by: { $0.1 > $1.1 })
        .map { (chain: $0.0, balance: $0.1.formatToFiat())}
    }
    
    var filteredChains: [Chain] {
        switch filterType {
        case .swap:
            return viewModel.groupedAssets.keys.compactMap { chainName in
                viewModel.groupedAssets[chainName]?.first?.chain
            }.filter(\.isSwapAvailable)
        case .send:
            return vault.coins.filter {$0.isNativeToken}.map{$0.chain}
        }
    }
}

#Preview {
    SwapChainPickerView(
        vault: Vault.example,
        showSheet: .constant(true),
        selectedChain: .constant(Chain.example)
    )
}
