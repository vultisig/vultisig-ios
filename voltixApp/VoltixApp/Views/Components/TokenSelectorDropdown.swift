//
//  TokenSelectorDropdown.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-15.
//

import SwiftUI

struct TokenSelectorDropdown: View {

    @Binding var coins: [Coin]
    @Binding var selected: Coin

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
            
            Text(selected.balanceString)

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
    
    private func getCell(for coin: Coin) -> some View {
        HStack(spacing: 12) {
            Image(coin.logo)
                .resizable()
                .frame(width: 32, height: 32)
                .cornerRadius(50)
            
            Text(coin.ticker)
                .font(.body16Menlo)
                .foregroundColor(.neutral0)
            
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
