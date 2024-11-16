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
}
#endif
