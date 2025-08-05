//
//  CoinPickerView.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 22.07.2024.
//

import SwiftUI

struct CoinPickerView: View {
    
    @State var searchText: String = .empty
    @State var isSearching = false

    @FocusState var isSearchFieldFocused: Bool

    @Environment(\.dismiss) var dismiss

    let coins: [Coin]
    let onSelect: ((Coin) -> Void)?

    var filtered: [Coin] {
        return coins.filter {
            $0.ticker.lowercased().contains(searchText.lowercased()) ||
            $0.chain.name.lowercased().contains(searchText.lowercased())
        }
    }

    var body: some View {
        content
            .onAppear {
                isSearchFieldFocused = true
            }
    }
    
    var searchBar: some View {
        HStack(spacing: 0) {
            Image(systemName: "magnifyingglass")
                .font(Theme.fonts.bodyLMedium)
                .foregroundColor(Theme.colors.textExtraLight)
            
            TextField(NSLocalizedString("search...", comment: "Search...").toFormattedTitleCase(), text: $searchText)
                .font(Theme.fonts.caption12)
                .foregroundColor(Theme.colors.textExtraLight)
                .submitLabel(.next)
                .disableAutocorrection(true)
                .textContentType(.oneTimeCode)
                .padding(.horizontal, 8)
                .borderlessTextFieldStyle()
                .maxLength($searchText)
                .colorScheme(.dark)

            if isSearching {
                Button {
                    searchText = ""
                    isSearchFieldFocused = false
                    isSearching = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Theme.colors.textExtraLight)
                }
                .foregroundColor(.blue)
                .font(Theme.fonts.caption12)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .padding(.horizontal, 12)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .onChange(of: searchText) { oldValue, newValue in
            isSearching = !newValue.isEmpty
        }
        .background(Color.blue600)
        .cornerRadius(12)
    }

    func row(for coin: Coin) -> some View {
        Button {
            onSelect?(coin)
            dismiss()
        } label: {
            CoinPickerCell(coin: coin)
        }
    }
    
    var scrollView: some View {
        LazyVStack(alignment: .leading, spacing: 24, pinnedViews: []) {
            if searchText.isEmpty {
                list
            } else {
                if filtered.count == 0 {
                    errorMessage
                } else {
                    filteredList
                }
            }

        }
    }
    
    var list: some View {
        ForEach(coins, id: \.self) { coin in
            row(for: coin)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }
    
    var filteredList: some View {
        ForEach(filtered, id: \.self) { coin in
            row(for: coin)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }
    
    var errorMessage: some View {
        ErrorMessage(text: "noResultFound")
            .frame(maxWidth: .infinity)
    }
}

#Preview {
    CoinPickerView(coins: [.example, .example, .example], onSelect: nil)
}
