//
//  ChainHeaderCell.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-26.
//

import SwiftUI

struct ChainHeaderCell: View {
    let group: GroupedChain
    
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
                    AddressQRCodeView(addressData: group.address, showSheet: $showQRcode)
                }
            }
    }
    
    var cell: some View {
        HStack(alignment: .top, spacing: 12) {
            logo
            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
        .background(Color.blue600)
    }
    
    var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            quantity
            address
        }
    }
    
    var header: some View {
        HStack(spacing: 12) {
            title
            Spacer()
            actions
        }
    }
    
    var logo: some View {
        Image(group.logo)
            .resizable()
            .frame(width: 32, height: 32)
            .cornerRadius(50)
            .padding(.top, 10)
    }
    
    var title: some View {
        Text(group.name.capitalized)
            .font(.body20MontserratSemiBold)
            .foregroundColor(.neutral0)
    }
    
    var actions: some View {
        HStack(spacing: 12) {
            showQRButton
            showTransactionsButton
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
    
    @ViewBuilder
    var showTransactionsButton: some View {
        
        if group.name == Chain.bitcoin.name {
            NavigationLink {
                TransactionsView(group: group)
            } label: {
                Image(systemName: "cube.transparent")
                    .foregroundColor(.neutral0)
                    .font(.body18MenloMedium)
            }
        } else {
            if let url = Endpoint.getExplorerByAddressURLByGroup(groupName: group.name, address: group.address),
               let linkURL = URL(string: url) {
                Link(destination: linkURL) {
                    Image(systemName: "cube.transparent")
                        .foregroundColor(.neutral0)
                        .font(.body18MenloMedium)
                }
            } else {
                EmptyView() 
            }
        }
    }
    
    var quantity: some View {
        Text(getQuantity())
            .font(.body12Menlo)
            .foregroundColor(.neutral100)
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
            .background(Color.blue400)
            .cornerRadius(50)
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
    
    private func getQuantity() -> String {
        guard group.coins.count>1 else {
            return "1 " + NSLocalizedString("asset", comment: "")
        }
        
        return "\(group.coins.count) \(NSLocalizedString("assets", comment: ""))"
    }
}

#Preview {
    ChainHeaderCell(group: GroupedChain.example)
}
