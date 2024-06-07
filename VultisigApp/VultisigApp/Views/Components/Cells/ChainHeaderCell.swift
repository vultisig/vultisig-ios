//
//  ChainHeaderCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-26.
//

import SwiftUI

struct ChainHeaderCell: View {
    let group: GroupedChain
    @Binding var isLoading: Bool
    
    @State var showAlert = false
    @State var showQRcode = false
    
    var body: some View {
        cell
            .alert(isPresented: $showAlert) {
                Alert(
                    title: Text(NSLocalizedString("addressCopied", comment: "")),
                    message: Text(group.address),
                    dismissButton: .default(Text(NSLocalizedString("ok", comment: "")))
                )
            }
            .sheet(isPresented: $showQRcode) {
                NavigationView {
                    AddressQRCodeView(addressData: group.address, showSheet: $showQRcode, isLoading: $isLoading)
                }
            }
    }
    
    var cell: some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
            .background(Color.blue600)
    }
    
    var logo: some View {
        Image(group.logo)
            .resizable()
            .frame(width: 32, height: 32)
            .cornerRadius(50)
    }
    
    var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            fiatBalance
            address
        }
    }
    
    var header: some View {
        HStack(spacing: 12) {
            logo
            title
            Spacer()
            actions
        }
    }
    
    var title: some View {
        Text(group.name.capitalized)
            .font(.body20MontserratSemiBold)
            .foregroundColor(.neutral0)
    }
    
    var actions: some View {
        HStack(spacing: 12) {
            copyButton
            showQRButton
            showTransactionsButton
        }
    }
    
    var fiatBalance: some View {
        Text(group.totalBalanceInFiatString)
            .font(.body20MenloBold)
            .foregroundColor(.neutral0)
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
            isLoading = true
            showQRcode.toggle()
        }, label: {
            Image(systemName: "qrcode")
                .foregroundColor(.neutral0)
                .font(.body18MenloMedium)
        })
    }
    
    var showTransactionsButton: some View {
        ZStack {
            webLink
        }
    }
    
    var transactionsViewLink: some View {
        NavigationLink {
            TransactionsView(group: group)
        } label: {
            Image(systemName: "cube")
                .foregroundColor(.neutral0)
                .font(.body18MenloMedium)
        }
    }
    
    var webLink: some View {
        ZStack {
            if let url = Endpoint.getExplorerByAddressURLByGroup(chain: group.coins.first?.chain, address: group.address),
               let linkURL = URL(string: url) {
                Link(destination: linkURL) {
                    Image(systemName: "cube")
                        .foregroundColor(.neutral0)
                        .font(.body18MenloMedium)
                }
            } else {
                EmptyView()
            }
        }
    }
    
    var address: some View {
        Text(group.address)
            .font(.body12Menlo)
            .foregroundColor(.turquoise600)
            .lineLimit(1)
    }
    
    private func copyAddress() {
        showAlert = true
        let pasteboard = UIPasteboard.general
        pasteboard.string = group.address
    }
}

#Preview {
    ChainHeaderCell(group: GroupedChain.example, isLoading: .constant(false))
}
