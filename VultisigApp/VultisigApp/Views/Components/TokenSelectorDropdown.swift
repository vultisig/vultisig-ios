//
//  TokenSelectorDropdown.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-15.
//

import SwiftUI

struct TokenSelectorDropdown: View {
    @Binding var coins: [Coin]
    @Binding var selected: Coin
    var balance: String? = nil

    var onSelect: ((Coin) -> Void)?

    @State var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            selectedCell
            
            if isActive && isExpanded {
                cells
            }
        }
        .padding(.horizontal, 12)
        .background(Color.blue600)
        .cornerRadius(10)
        .disabled(!isActive)
    }
    
    var selectedCell: some View {
        Button {
            withAnimation {
                isExpanded.toggle()
            }
        } label: {
            cell
        }
    }
    
    var cell: some View {
        HStack(spacing: 12) {
            image
            Text("\(selected.ticker)")
            Spacer()
            balanceContent

            if isActive {
                Image(systemName: "chevron.down")
            }
        }
        .redacted(reason: selected.balanceString.isEmpty ? .placeholder : [])
        .font(.body16Menlo)
        .foregroundColor(.neutral0)
        .frame(height: 48)
    }
    
    var image: some View {
        Image(selected.logo)
            .resizable()
            .frame(width: 32, height: 32)
            .cornerRadius(100)
    }
    
    var cells: some View {
        ForEach(coins, id: \.self) { coin in
            Button {
                handleSelection(for: coin)
            } label: {
                VStack(spacing: 0) {
                    Separator()
                    getCell(for: coin)
                }
            }
        }
    }
    
    var balanceContent: some View {
        HStack(spacing: 0) {
            Group {
                Text(NSLocalizedString("balance", comment: "")) +
                Text(": ")
            }
            
            if let balance {
                Text(balance)
            } else {
                Text(selected.balanceString)
            }
        }
        .font(.body12Menlo)
        .foregroundColor(.neutral200)
    }
    
    private func getCell(for coin: Coin) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Image(coin.logo)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(50)

                if let chainIcon = coin.tokenChainLogo {
                    Image(chainIcon)
                        .resizable()
                        .frame(width: 16, height: 16)
                        .cornerRadius(16)
                        .offset(x: 12, y: 12)
                }
            }

            Text(coin.ticker)
                .font(.body16Menlo)
                .foregroundColor(.neutral0)

            if let schema = coin.tokenSchema {
                Text("(\(schema))")
                    .font(.body16Menlo)
                    .foregroundColor(.neutral0)
            }

            Spacer()
            
            if selected == coin {
                Image(systemName: "checkmark")
                    .font(.body16Menlo)
                    .foregroundColor(.neutral0)
            }
        }
        .frame(height: 48)
    }

    var isActive: Bool {
        return coins.count > 1
    }

    private func handleSelection(for coin: Coin) {
        isExpanded = false
        selected = coin
        onSelect?(coin)
    }
}

#Preview {
    TokenSelectorDropdown(coins: .constant([.example]), selected: .constant(.example))
}
