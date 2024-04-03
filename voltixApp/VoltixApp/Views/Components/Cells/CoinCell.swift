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
    
    @StateObject var sendTx = SendTransaction()
    @StateObject var swapTx = SwapTransaction()
    @StateObject var coinViewModel = CoinViewModel()
	
    var body: some View {
        cell
            .task {
                await setData()
            }
    }
    
    var cell: some View {
        VStack(alignment: .leading, spacing: 15) {
            header
            amount
            buttons
        }
        .padding(16)
        .background(Color.blue600)
    }
    
    var header: some View {
        HStack {
            title
            Spacer()
            quantity
        }
    }
    
    var title: some View {
        Text(sendTx.coin.ticker)
            .font(.body20Menlo)
            .foregroundColor(.neutral0)
    }
    
    var quantity: some View {
        Text(coinViewModel.coinBalance ?? "0.0")
            .font(.body16Menlo)
            .foregroundColor(.neutral0)
    }
    
    var amount: some View {
        let balance = coinViewModel.balanceUSD
        
        return Text(balance ?? "0.0000")
            .font(.body16MenloBold)
            .foregroundColor(.neutral0)
            .redacted(reason: balance==nil ? .placeholder : [])
    }
    
    var buttons: some View {
        let isDisabled = coinViewModel.balanceUSD == nil
        
        return HStack(spacing: 20) {
            swapButton
            sendButton
        }
        .disabled(isDisabled)
        .redacted(reason: isDisabled ? .placeholder : [])
    }
    
    var swapButton: some View {
        NavigationLink {
            SwapCryptoView(tx: swapTx, coinViewModel: coinViewModel, group: group)
        } label: {
            Text(NSLocalizedString("swap", comment: "Swap button text").uppercased())
                .font(.body16MenloBold)
                .foregroundColor(.persianBlue200)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
                .background(Color.blue800)
                .cornerRadius(50)
        }
    }
    
    var sendButton: some View {
        NavigationLink {
            SendCryptoView(tx: sendTx,
                           coinViewModel: coinViewModel,
                           group: group,
                           vault: vault)
        } label: {
            Text(NSLocalizedString("send", comment: "Send button text").uppercased())
                .font(.body16MenloBold)
                .foregroundColor(.turquoise600)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
                .background(Color.blue800)
                .cornerRadius(50)
        }
    }
    
    private func setData() async {
        sendTx.coin = coin
        swapTx.fromCoin = coin

        await coinViewModel.loadData(coin: coin)
    }
}

#Preview {
    CoinCell(coin: Coin.example, group: GroupedChain.example, vault: Vault.example)
}
