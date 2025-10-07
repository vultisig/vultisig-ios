//
//  ReceiveChainSelectionScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 26/09/2025.
//

import SwiftUI

struct ReceiveChainSelectionScreen: View {
    let vault: Vault
    @Binding var isPresented: Bool
    @ObservedObject var viewModel: VaultDetailViewModel
    
    @State var showBottomSheet: Bool = false
    @State var selectedCoin: Coin?
    
    init(vault: Vault, isPresented: Binding<Bool>, viewModel: VaultDetailViewModel) {
        self.vault = vault
        self._isPresented = isPresented
        self.viewModel = viewModel
    }
    
    var body: some View {
        Screen(title: "selectChain".localized) {
            VStack(spacing: 12) {
                SearchTextField(value: $viewModel.searchText)
                ScrollView {
                    if !viewModel.filteredGroups.isEmpty {
                        list
                    } else {
                        emptyMessage
                    }
                }
                .cornerRadius(12)
            }
        }
        .applySheetSize()
        .sheetStyle()
        .onDisappear { viewModel.searchText = "" }
        .crossPlatformSheet(item: $selectedCoin) {
            ReceiveQRCodeBottomSheet(
                coin: $0,
                isNativeCoin: true
            ) {
                isPresented = false
            }
        }
    }
    
    var list: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(viewModel.filteredGroups.enumerated()), id: \.element.name) { offset, chain in
                cell(for: chain)
                    .commonListItemContainer(index: offset, itemsCount: viewModel.filteredGroups.count)
            }
        }
    }
    
    func cell(for chain: GroupedChain) -> some View {
        Button {
            selectedCoin = chain.nativeCoin
            showBottomSheet = true
        } label: {
            HStack {
                ReceiveChainSelectionRowView(chain: chain.chain)
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(Theme.colors.bgSecondary)
        }
    }
    
    var emptyMessage: some View {
        ErrorMessage(text: "noResultFound")
            .padding(.top, 48)
    }
}

struct ReceiveChainSelectionRowView: View {
    let chain: Chain
    
    var body: some View {
        HStack {
            iconImage
            nameText
        }
    }
    
    var iconImage: some View {
        AsyncImageView(
            logo: chain.logo,
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
    ReceiveChainSelectionScreen(vault: .example, isPresented: .constant(true), viewModel: .init())
}
