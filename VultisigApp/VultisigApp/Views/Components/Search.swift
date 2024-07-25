//
//  Search.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-25.
//

import SwiftUI

struct Search: View {
    @Binding var searchText: String
    var cornerRadius: CGFloat = 10

    var body: some View {
        HStack(spacing: 12) {
            searchIcon

            textField

            if searchText != "" {
                closeButton
            }
        }
        .padding(18)
        .background(Color.blue600)
        .cornerRadius(cornerRadius)
        .colorScheme(.dark)
    }

    var textField: some View {
        TextField(NSLocalizedString("search", comment: ""), text: $searchText)
            .foregroundColor(.neutral700)
            .font(.body14Menlo)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()

                    Button {
                        hideKeyboard()
                    } label: {
                        Text(NSLocalizedString("done", comment: ""))
                    }
                }
            }
    }

    var searchIcon: some View {
        Image(systemName: "magnifyingglass")
            .resizable()
            .frame(width: 24, height: 24)
            .foregroundColor(.neutral500)
    }

    var closeButton: some View {
        Button {
            clearSearchText()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .resizable()
                .frame(width: 20, height: 20)
                .foregroundColor(.neutral500)
        }
    }

    private func clearSearchText() {
        searchText = ""
    }
}

#Preview {
    Search(searchText: .constant(""))
}
