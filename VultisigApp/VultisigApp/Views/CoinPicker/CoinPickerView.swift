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
}

#Preview {
    CoinPickerView(coins: [.example, .example, .example], onSelect: nil)
}
