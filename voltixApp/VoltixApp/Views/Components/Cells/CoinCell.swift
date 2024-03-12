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
    @State var showAlert = false
    
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
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text(NSLocalizedString("addressCopied", comment: "")),
                message: Text(coin.address),
                dismissButton: .default(Text(NSLocalizedString("ok", comment: "")))
            )
        }
        .sheet(isPresented: $showQRcode) {
            NavigationView {
                AddressQRCodeView(addressData: coin.address, showSheet: $showQRcode)
            }
        }
    }
    
    var main: some View {
        Button(action: {
            expandCell()
        }, label: {
            card
        })
    }
    
    var image: some View {
        HStack {
            
        }
    }
    
    var card: some View {
        HStack {
            image
            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
    }
    
    var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            amount
            address
        }
    }
    
    var header: some View {
        HStack {
            title
            Spacer()
            actions
        }
    }
    
    var title: some View {
        Text(coin.chain.name.capitalized)
            .font(.body20MontserratSemiBold)
            .foregroundColor(.neutral0)
    }
    
    var actions: some View {
        HStack(spacing: 12) {
            showQRButton
            copyButton
        }
    }
    
    var copyButton: some View {
        Button {
            copyAddress()
        } label: {
            Image(systemName: "square.on.square")
                .foregroundColor(.neutral0)
                .font(.body18MenloMedium)
        }
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
    
    private func copyAddress() {
        showAlert = true
        let pasteboard = UIPasteboard.general
        pasteboard.string = coin.address
    }
}

#Preview {
    ScrollView {
        CoinCell(presentationStack: .constant([]), coin: Coin.example)
    }
}
