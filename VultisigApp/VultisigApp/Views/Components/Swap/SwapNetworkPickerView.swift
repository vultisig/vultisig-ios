//
//  SwapNetworkPickerView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-03-26.
//

import SwiftUI

struct SwapNetworkPickerView: View {
    @Binding var showSheet: Bool
    @Binding var chain: Chain?

    @EnvironmentObject var viewModel: CoinSelectionViewModel

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
        .padding(.horizontal, 16)
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
            VStack(spacing: 24) {
                searchBar

                ForEach(viewModel.filteredChains, id: \.self) { key in
                    ChainSelectionCell(
                        assets: viewModel.groupedAssets[key] ?? [],
                        showAlert: $showAlert
                    )
                }
            }
            .padding(.vertical, 8)
            .padding(.bottom, UIDevice.current.userInterfaceIdiom == .pad ? 50 : 0)
            .padding(.horizontal, 16)
        }
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
    }

    var searchField: some View {
        TextField(NSLocalizedString("Search", comment: "Search"), text: $viewModel.searchText)
            .font(.body16Menlo)
            .foregroundColor(.neutral0)
            .disableAutocorrection(true)
            .padding(.horizontal, 8)
            .borderlessTextFieldStyle()
            .colorScheme(.dark)
    }
}

#Preview {
    SwapNetworkPickerView(showSheet: .constant(true), chain: .constant(nil))
}
