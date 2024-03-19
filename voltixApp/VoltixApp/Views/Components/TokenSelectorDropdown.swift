//
//  TokenSelectorDropdown.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-15.
//

import SwiftUI

struct TokenSelectorDropdown: View {
    @ObservedObject var tx: SendTransaction
    @ObservedObject var coinViewModel: CoinViewModel
    let group: GroupedChain
    
    @State var isActive = false
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
        .onAppear {
            setData()
        }
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
            Text("\(tx.coin.ticker)")
            Spacer()
            Text(coinViewModel.coinBalance ?? "0")
            
            if isActive {
                Image(systemName: "chevron.down")
            }
        }
        .font(.body16Menlo)
        .foregroundColor(.neutral0)
        .frame(height: 48)
        .redacted(reason: coinViewModel.coinBalance==nil ? .placeholder : [])
    }
    
    var image: some View {
        Image(tx.coin.ticker.lowercased())
            .resizable()
            .frame(width: 32, height: 32)
            .cornerRadius(100)
    }
    
    var cells: some View {
        ForEach(group.coins, id: \.self) { coin in
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
            
            if tx.coin == coin {
                Image(systemName: "checkmark")
                    .font(.body16Menlo)
                    .foregroundColor(.neutral0)
            }
        }
        .frame(height: 48)
    }
    
    private func setData() {
        isActive = group.coins.count>1
    }
    
    private func handleSelection(for coin: Coin) {
        isExpanded = false
        tx.coin = coin
    }
}

#Preview {
    TokenSelectorDropdown(tx: SendTransaction(), coinViewModel: CoinViewModel(), group: GroupedChain.example)
}
