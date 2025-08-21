//
//  AddressBookChainSelectionScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/08/2025.
//

import SwiftUI

struct AddressBookChainSelectionScreen: View {
    @Binding var selectedChain: AddressBookChainType
    @StateObject var viewModel: AddressBookChainSelectionViewModel
    
    @Environment(\.dismiss) var dismiss
    
    init(selectedChain: Binding<AddressBookChainType>, vaultChains: [CoinMeta]) {
        self._selectedChain = selectedChain
        self._viewModel = StateObject(wrappedValue: AddressBookChainSelectionViewModel(vaultChains: vaultChains))
    }
    
    var body: some View {
        Screen(title: "selectChain".localized) {
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
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        dismiss()
                    }
                }
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
            label
        }
    }
    
    var label: some View {
        VStack(spacing: 0) {
            content
            GradientListSeparator()
        }
        .background(isSelected ? Theme.colors.bgTertiary : Theme.colors.bgSecondary)
    }
    
    var content: some View {
        HStack {
            AddressBookChainView(chain: chain)
            Spacer()
            check
                .showIf(isSelected)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
    }
    
    var check: some View {
        Image(systemName: "checkmark")
            .font(Theme.fonts.caption12)
            .foregroundColor(Theme.colors.alertInfo)
            .frame(width: 24, height: 24)
            .background(Theme.colors.bgSecondary)
            .cornerRadius(32)
            .bold()
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
    AddressBookChainSelectionScreen(selectedChain: .constant(.evm), vaultChains: [])
}
