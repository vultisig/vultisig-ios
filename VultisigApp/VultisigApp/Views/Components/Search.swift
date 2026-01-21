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
        .background(Theme.colors.bgSurface1)
        .cornerRadius(cornerRadius)
        .colorScheme(.dark)
    }

    var searchIcon: some View {
        Image(systemName: "magnifyingglass")
            .resizable()
            .frame(width: 24, height: 24)
            .foregroundColor(Theme.colors.textTertiary)
    }

    var closeButton: some View {
        Button {
            clearSearchText()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .resizable()
                .frame(width: 20, height: 20)
                .foregroundColor(Theme.colors.textTertiary)
        }
    }

    private func clearSearchText() {
        searchText = ""
    }
}

#Preview {
    Search(searchText: .constant(""))
}
