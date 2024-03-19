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
    
    @StateObject var tx = SendTransaction()
    @StateObject var coinViewModel = CoinViewModel()
    @StateObject var utxoBtc = BitcoinUnspentOutputsService()
    @StateObject var utxoLtc = LitecoinUnspentOutputsService()
    @StateObject var eth = EthplorerAPIService()
    @StateObject var thor = ThorchainService.shared
	
    var body: some View {
        cell
            .onAppear {
                Task {
                    await setData()
                }
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
        Text(tx.coin.ticker)
            .font(.body20Menlo)
            .foregroundColor(.neutral0)
    }
    
    var quantity: some View {
        let balance = coinViewModel.coinBalance
        
        return Text(balance ?? "0.00001")
            .font(.body16Menlo)
            .foregroundColor(.neutral0)
            .redacted(reason: balance==nil ? .placeholder : [])
    }
    
    var amount: some View {
        let balance = coinViewModel.balanceUSD
        
        return Text(balance ?? "US$1000")
            .font(.body16MenloBold)
            .foregroundColor(.neutral0)
            .redacted(reason: balance==nil ? .placeholder : [])
    }
    
    var buttons: some View {
        HStack(spacing: 20) {
            swapButton
            sendButton
        }
    }
    
    var swapButton: some View {
        NavigationLink {
            SendInputDetailsView(presentationStack: .constant([]), tx: tx)
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
            SendCryptoView(tx: tx, group: group)
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
        tx.coin = coin
        tx.gas = "20"
        
        await coinViewModel.loadData(
            utxoBtc: utxoBtc,
            utxoLtc: utxoLtc,
            eth: eth,
            thor: thor,
            tx: tx
        )
    }
}

#Preview {
    CoinCell(coin: Coin.example, group: GroupedChain.example)
}
