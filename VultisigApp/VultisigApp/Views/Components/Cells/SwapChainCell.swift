//
//  SwapChainCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-03-26.
//

import SwiftUI

struct SwapChainCell: View {
    let coins: [Coin]
    let chain: Chain
    @Binding var selectedCoin: Coin
    @Binding var selectedChain: Chain?
    @Binding var showSheet: Bool
    
    @State var isSelected = false
    
    var body: some View {
        Button {
            handleTap()
        } label: {
            label
        }
        .onAppear {
            setData()
        }
    }
    
    var label: some View {
        VStack(spacing: 0) {
            content
            Separator()
                .opacity(0.2)
        }
        .background(isSelected ? Color.blue400 : Color.blue600)
    }
    
    var content: some View {
        HStack {
            icon
            title
            Spacer()
            
            if isSelected {
                check
            } else {
                balanceInfo
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
    }
    
    var icon: some View {
        Image(chain.logo)
            .resizable()
            .frame(width: 32, height: 32)
    }
    
    var title: some View {
        Text(chain.name)
            .font(.body14BrockmannMedium)
            .foregroundColor(.neutral0)
    }
    
    var check: some View {
        Image(systemName: "checkmark")
            .font(.body12BrockmannMedium)
            .foregroundColor(.alertTurquoise)
            .frame(width: 24, height: 24)
            .background(Color.blue600)
            .cornerRadius(32)
            .bold()
    }
    
    var balanceInfo: some View {
        Text(totalUSDValue)
            .font(.body12BrockmannMedium)
            .foregroundColor(.extraLightGray)
    }
    
    private func setData() {
        isSelected = chain == selectedChain
    }
    
    private func handleTap() {
        selectedChain = chain
        
        let availableCoins = coins.filter { coin in
            coin.chain == selectedChain
        }.sorted {
            $0.ticker < $1.ticker
        }
        
        if let firstCoin = availableCoins.first {
            selectedCoin = firstCoin
        }
        
        showSheet = false
    }
    
    private var totalUSDValue: String {
        let totalValue = coins
            .filter { $0.chain == chain }
            .reduce(Decimal.zero) { sum, coin in
                sum + coin.balanceInFiatDecimal
            }
        return totalValue.formatToFiat()
    }
}

#Preview {
    SwapChainCell(
        coins: [],
        chain: Chain.example,
        selectedCoin: .constant(Coin.example),
        selectedChain: .constant(Chain.example),
        showSheet: .constant(true)
    )
}
