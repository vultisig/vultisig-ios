//
//  CoinCell.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-08.
//

import SwiftUI

struct CoinCell: View {
    let coin: Coin
    
    @StateObject var tx = SendTransaction()
    @StateObject var coinViewModel = CoinViewModel()
    @StateObject var utxoBtc = BitcoinUnspentOutputsService()
	@StateObject var utxoLtc = LitecoinUnspentOutputsService()
    @StateObject var eth = EthplorerAPIService()
    @StateObject var thor = ThorchainService.shared
	@StateObject var blockchair = BlockchairService.shared
	
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
        Text(coinViewModel.coinBalance)
            .font(.body16Menlo)
            .foregroundColor(.neutral0)
    }
    
    var amount: some View {
        Text(coinViewModel.balanceUSD)
            .font(.body16MenloBold)
            .foregroundColor(.neutral0)
    }
    
    var buttons: some View {
        HStack(spacing: 20) {
            swapButton
            sendButton
        }
    }
    
    var swapButton: some View {
        NavigationLink {
            SwapCryptoView()
        } label: {
            Text(NSLocalizedString("swap", comment: "Swap button text").uppercased())
                .font(.body16MenloBold)
                .foregroundColor(.blue200)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
                .background(Color.blue800)
                .cornerRadius(50)
        }
    }
    
    var sendButton: some View {
        NavigationLink {
            SendInputDetailsView(presentationStack: .constant([]), tx: tx)
//            SendCryptoView()
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
        
        await coinViewModel.loadData(
			utxoBtc: utxoBtc,
			utxoLtc: utxoLtc,
            eth: eth,
            thor: thor,
            tx: tx,
			blockchair: blockchair
        )
    }
}

#Preview {
    CoinCell(coin: Coin.example)
}
