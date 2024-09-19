//
//  CoinPickerView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-18.
//

#if os(macOS)
import SwiftUI

extension CoinPickerView {
    var content: some View {
        ZStack {
            Background()
            main
        }
        .navigationBarBackButtonHidden(true)
    }
    
    var main: some View {
        VStack(spacing: 0) {
            headerMac
            view
        }
    }
    
    var headerMac: some View {
        GeneralMacHeader(title: "chooseTokens")
    }
    
    var view: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchBar
                .padding(.vertical, 18)
                .padding(.horizontal, 40)

            Separator()
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24, pinnedViews: []) {
                    if searchText.isEmpty {
                        Section(header: header(label: "tokens")) {
                            ForEach(coins, id: \.self) { coin in
                                row(for: coin)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                            }
                        }
                    } else {
                        Section(header: header(label: "searchResult")) {
                            ForEach(filtered, id: \.self) { coin in
                                row(for: coin)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                            }
                        }
                    }

                }
                .padding(.horizontal, 12)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 40)
                .padding(.top, 20)
                .padding(.bottom, 50)
                .colorScheme(.dark)
            }
        }
    }
    
    var searchBar: some View {
        HStack(spacing: 0) {
            TextField(NSLocalizedString("Search", comment: "Search").toFormattedTitleCase(), text: $searchText)
                .font(.body16Menlo)
                .foregroundColor(.neutral0)
                .submitLabel(.next)
                .disableAutocorrection(true)
                .textContentType(.oneTimeCode)
                .padding(.horizontal, 8)
                .borderlessTextFieldStyle()
                .maxLength($searchText)
                .colorScheme(.dark)

            if isSearching {
                Button("Cancel") {
                    searchText = ""
                    isSearchFieldFocused = false
                    isSearching = false
                }
                .foregroundColor(.blue)
                .font(.body12Menlo)
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
}
#endif
