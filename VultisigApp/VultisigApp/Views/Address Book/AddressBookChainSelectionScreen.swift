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

    var body: some View {
        Screen(showNavigationBar: false) {
            VStack(spacing: 12) {
                SearchTextField(value: $viewModel.searchText)
                ScrollView(showsIndicators: false) {
                    if !viewModel.filteredChains.isEmpty {
                        list
                    } else {
                        emptyMessage
                    }
                }
                .cornerRadius(12)
            }
        }
        .applySheetSize()
        .onLoad(perform: viewModel.setup)
        .crossPlatformToolbar("selectChain".localized, showsBackButton: false) {
            CustomToolbarItem(placement: .leading) {
                ToolbarButton(image: "x") {
                    isPresented.toggle()
                }
            }
        }
    }

    var list: some View {
        LazyVStack(spacing: 0) {
            ForEach(viewModel.filteredChains) { chain in
                AddressBookChainCell(
                    chain: chain,
                    isSelected: selectedChain == chain
                ) {
                    selectedChain = chain
                    isPresented.toggle()
                }
                GradientListSeparator()
                    .showIf(chain != viewModel.filteredChains.last)
            }
        }
    }

    var emptyMessage: some View {
        ErrorMessage(text: "noResultFound")
            .padding(.top, 48)
    }
}

#Preview {
    AddressBookChainSelectionScreen(selectedChain: .constant(.evm), isPresented: .constant(true), vaultChains: [])
}
