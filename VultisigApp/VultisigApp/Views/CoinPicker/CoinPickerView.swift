//
//  CoinPickerView.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 22.07.2024.
//

import SwiftUI

struct CoinPickerView: View {

    @State private var searchText: String = .empty
    @State private var isSearching = false

    @FocusState private var isSearchFieldFocused: Bool

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
        ZStack {
            Background()
            main
        }
        .navigationBarBackButtonHidden(true)
#if os(iOS)
        .navigationTitle(NSLocalizedString("chooseTokens", comment: "Choose Tokens"))
        .toolbar {
            ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "chevron.backward")
                        .font(.body18MenloBold)
                        .foregroundColor(Color.neutral0)
                }
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
#endif
        .onAppear {
            isSearchFieldFocused = true
        }
    }
    
    var main: some View {
        VStack(spacing: 0) {
#if os(macOS)
            headerMac
#endif
            view
        }
    }
    
    var headerMac: some View {
        GeneralMacHeader(title: "chooseTokens")
    }

    var view: some View {
        VStack(alignment: .leading, spacing: 0) {
#if os(macOS)
            searchBar
                .padding(.vertical, 18)
                .padding(.horizontal, 40)

            Separator()
#endif
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
#if os(iOS)
                .listStyle(.grouped)
#elseif os(macOS)
                .padding(.horizontal, 40)
                .padding(.top, 20)
                .padding(.bottom, 50)
                .colorScheme(.dark)
#endif
            }
        }
#if os(iOS)
        .padding(.bottom, 50)
#endif
    }

    func header(label: String) -> some View {
        VStack {
            Spacer()
            Text(NSLocalizedString(label, comment:"").uppercased())
                .font(.body14Menlo)
                .foregroundColor(Color.neutral300)
                .padding(.horizontal, 12)
        }
        .frame(height: 44)
    }

    func row(for coin: Coin) -> some View {
        Button {
            onSelect?(coin)
            dismiss()
        } label: {
            HStack(spacing: 16) {
                AsyncImageView(
                    logo: coin.logo,
                    size: CGSize(width: 32, height: 32),
                    ticker: coin.ticker,
                    tokenChainLogo: coin.chain.logo
                )
                VStack(alignment: .leading, spacing: 6) {
                    Text(coin.ticker)
                        .font(.body16MontserratBold)
                        .foregroundColor(.neutral0)

                    Text(coin.chain.name)
                        .font(.body12MontserratSemiBold)
                        .foregroundColor(.neutral0)
                }
                Spacer()
            }
            .frame(height: 72)
            .padding(.horizontal, 16)
            .background(Color.blue600)
            .cornerRadius(10)
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
#if os(iOS)
                .focused($isSearchFieldFocused)
                .textInputAutocapitalization(.never)
                .keyboardType(.default)
#elseif os(macOS)
                .colorScheme(.dark)
#endif

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

#Preview {
    CoinPickerView(coins: [.example, .example, .example], onSelect: nil)
}
