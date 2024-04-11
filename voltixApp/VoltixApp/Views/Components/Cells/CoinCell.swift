//
//  CoinCell.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-08.
//

import SwiftUI

struct CoinCell: View {
    let coin: Coin
    let group: GroupedChain
    let vault: Vault
    
    @StateObject var coinViewModel = CoinViewModel()
	
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            header
            amount
        }
        .padding(16)
        .background(Color.blue600)
        .onAppear {
            Task {
                await setData()
            }
        }
    }
    
    var header: some View {
        HStack {
            title
            Spacer()
            quantity
        }
    }
    
    var title: some View {
        Text(coin.ticker)
            .font(.body20Menlo)
            .foregroundColor(.neutral0)
    }
    
    var quantity: some View {
        Text(coin.balanceString)
            .font(.body16Menlo)
            .foregroundColor(.neutral0)
    }
    
    var amount: some View {
        Text(coin.balanceInFiat)
            .font(.body16MenloBold)
            .foregroundColor(.neutral0)
    }
    
    private func setData() async {
        await coinViewModel.loadData(coin: coin)
    }
}

#Preview {
    CoinCell(coin: Coin.example, group: GroupedChain.example, vault: Vault.example)
}
