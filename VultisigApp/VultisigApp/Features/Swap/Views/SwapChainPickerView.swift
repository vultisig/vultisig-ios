//
//  SwapChainPickerView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-03-26.
//

import SwiftUI

enum ChainFilterType {
    case swap
    case send
}

struct SwapChainPickerView: View {
    let filterType: ChainFilterType
    let vault: Vault
    @Binding var showSheet: Bool
    @Binding var selectedChain: Chain?

    @State var searchBarFocused: Bool = false
    @EnvironmentObject var viewModel: CoinSelectionViewModel

    init(
        filterType: ChainFilterType = .send,
        vault: Vault,
        showSheet: Binding<Bool>,
        selectedChain: Binding<Chain?>
    ) {
        self.filterType = filterType
        self.vault = vault
        self._showSheet = showSheet
        self._selectedChain = selectedChain
    }

    var body: some View {
        container
    }

    var container: some View {
#if os(iOS)
        NavigationStack {
            content
        }
#else
        content
            .presentationSizingFitted()
            .applySheetSize()
            .transaction { $0.disablesAnimations = true }
#endif
    }

    var content: some View {
        VStack(spacing: 12) {
            searchBar
            ScrollView {
                VStack(spacing: 12) {
                    if !viewModel.filteredChains.isEmpty {
                        listHeader
                        list
                    } else {
                        emptyMessage
                    }
                }
                .padding(.bottom, 50)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
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
        .onDisappear { viewModel.searchText = "" }
    }

    var listHeader: some View {
        HStack {
            Text(NSLocalizedString("chain", comment: ""))
                .font(Theme.fonts.caption12)
                .foregroundColor(Theme.colors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
            Text(NSLocalizedString("balance", comment: ""))
                .font(Theme.fonts.caption12)
                .foregroundColor(Theme.colors.textTertiary)
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

    var searchBar: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("selectChain".localized)
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
        viewModel.filterChains(type: filterType, vault: vault)
    }
}

#Preview {
    SwapChainPickerView(
        vault: Vault.example,
        showSheet: .constant(true),
        selectedChain: .constant(Chain.example)
    )
}
