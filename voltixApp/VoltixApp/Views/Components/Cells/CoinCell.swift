//
//  CoinCell.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-08.
//

import SwiftUI

struct CoinCell: View {
    @Binding var presentationStack: [CurrentScreen]
    let coin: Coin
    
    @StateObject var tx = SendTransaction()
    @StateObject var coinViewModel = CoinViewModel()
    @StateObject var uxto = UnspentOutputsService()
    @StateObject var eth = EthplorerAPIService()
    @StateObject var thor = ThorchainService.shared
    
    @State var isExpanded = false
    @State var showQRcode = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            main
            
            if isExpanded {
                cells
            }
        }
        .padding(.vertical, 4)
        .background(Color.blue600)
        .cornerRadius(10)
        .padding(.horizontal, 16)
        .clipped()
        .onAppear {
            Task {
                await setData()
            }
        }
        .sheet(isPresented: $showQRcode) {
            AddressQRCodeView()
        }
    }
    
    var main: some View {
        Button(action: {
            expandCell()
        }, label: {
            card
        })
    }
    
    var card: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            address
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
    }
    
    var header: some View {
        HStack(spacing: 12) {
            title
            actions
            Spacer()
            amount
        }
    }
    
    var title: some View {
        Text(coin.chain.name.capitalized)
            .font(.body20MontserratSemiBold)
            .foregroundColor(.neutral0)
    }
    
    var actions: some View {
        HStack(spacing: 12) {
            copyButton
            showQRButton
        }
    }
    
    var copyButton: some View {
        Image(systemName: "square.on.square")
            .foregroundColor(.neutral0)
            .font(.body18MenloMedium)
    }
    
    var showQRButton: some View {
        Button(action: {
            showQRcode.toggle()
        }, label: {
            Image(systemName: "qrcode")
                .foregroundColor(.neutral0)
                .font(.body18MenloMedium)
        })
    }
    
    var amount: some View {
        Text(coinViewModel.balanceUSD)
            .font(.body20MontserratSemiBold)
            .foregroundColor(.neutral0)
    }
    
    var address: some View {
        Text(coin.address)
            .font(.body12Menlo)
            .foregroundColor(.turquoise600)
            .lineLimit(1)
    }
    
    var cells: some View {
        VStack(spacing: 0) {
            Separator()
            AssetCell(
                presentationStack: $presentationStack, 
                tx: tx,
                viewModel: coinViewModel
            )
        }
    }
    
    private func setData() async {
        tx.coin = coin
        await coinViewModel.loadData(
            uxto: uxto,
            eth: eth,
            thor: thor,
            tx: tx
        )
    }
    
    private func expandCell() {
        withAnimation {
            isExpanded.toggle()
        }
    }
}

#Preview {
    ScrollView {
        CoinCell(presentationStack: .constant([]), coin: Coin.example)
    }
}
