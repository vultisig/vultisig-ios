//
//  AddressBookChainSelectionScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/08/2025.
//

import SwiftUI

struct AddressBookChainSelectionScreen: View {
    @Binding var selectedChain: AddressBookChainType
    @Binding var isPresented: Bool
    @StateObject var viewModel: AddressBookChainSelectionViewModel

    init(selectedChain: Binding<AddressBookChainType>, isPresented: Binding<Bool>, vaultChains: [CoinMeta]) {
        self._selectedChain = selectedChain
        self._isPresented = isPresented
        self._viewModel = StateObject(wrappedValue: AddressBookChainSelectionViewModel(vaultChains: vaultChains))
    }

    private var sections: [AssetSection<Int, AddressBookChainType>] {
        viewModel.filteredChains.isEmpty ? [] : [AssetSection(assets: viewModel.filteredChains)]
    }

    var body: some View {
        AssetSelectionContainerSheet(
            title: "selectChain".localized,
            isPresented: $isPresented,
            searchText: $viewModel.searchText,
            elements: sections,
            showsConfirmButton: false,
            onSave: {},
            cellBuilder: { chain, _ in
                AssetSelectionGridCell(
                    name: chain.name,
                    ticker: .empty,
                    logo: chain.icon,
                    isSelected: .constant(selectedChain == chain)
                ) {
                    selectedChain = chain
                    isPresented = false
                }
            },
            emptyStateBuilder: {
                ChainNotFoundEmptyStateView()
            }
        )
        .onLoad(perform: viewModel.setup)
    }
}

#Preview {
    AddressBookChainSelectionScreen(selectedChain: .constant(.evm), isPresented: .constant(true), vaultChains: [])
}
