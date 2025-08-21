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
        VStack {
            SheetHeaderView(title: "selectChain".localized, isPresented: $isPresented)
                .padding(.top, 12)
            VStack(spacing: 12) {
                SearchTextField(value: $viewModel.searchText, isFocused: .init())
                ScrollView {
                    if !viewModel.filteredChains.isEmpty {
                        list
                    } else {
                        emptyMessage
                    }
                }
                .cornerRadius(12)
            }
        }
        .onLoad(perform: viewModel.setup)
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

struct AddressBookChainCell: View {
    let chain: AddressBookChainType
    let isSelected: Bool
    var onSelect: () -> Void
    
    init(chain: AddressBookChainType, isSelected: Bool = false, onSelect: @escaping () -> Void = {}) {
        self.chain = chain
        self.isSelected = isSelected
        self.onSelect = onSelect
    }
    
    var body: some View {
        Button {
            onSelect()
        } label: {
            HStack {
                AddressBookChainView(chain: chain)
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(isSelected ? Theme.colors.bgTertiary : Theme.colors.bgSecondary)
        }
    }
}

struct AddressBookChainView: View {
    let chain: AddressBookChainType
    
    var body: some View {
        HStack {
            iconImage
            nameText
        }
    }
    
    var iconImage: some View {
        AsyncImageView(
            logo: chain.icon,
            size: CGSize(width: 32, height: 32),
            ticker: "",
            tokenChainLogo: nil
        )
    }
    
    var nameText: some View {
        Text(chain.name)
            .font(Theme.fonts.bodySMedium)
            .foregroundColor(Theme.colors.textPrimary)
    }
}

#Preview {
    AddressBookChainSelectionScreen(selectedChain: .constant(.evm), isPresented: .constant(true), vaultChains: [])
}
