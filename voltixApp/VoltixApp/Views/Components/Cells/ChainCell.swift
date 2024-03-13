//
//  ChainCell.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-08.
//

import SwiftUI
import SDWebImageSwiftUI

struct ChainCell: View {
    let group: GroupedChain
    
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
    
    var main: some View {
        Button(action: {
            expandCell()
        }, label: {
            card
        })
    }
    
    var progressView: some View {
        ProgressView()
            .tint(.black)
            .frame(width: 32, height: 32)
            .background(Color.neutral200)
            .cornerRadius(100)
    }
    
    var card: some View {
        HStack {
//            image
            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
    }
    
    var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            quantity
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
        Text(group.name.capitalized)
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
    
    var quantity: some View {
        Text("assets")
            .font(.body20MontserratSemiBold)
            .foregroundColor(.neutral0)
    }
    
    var address: some View {
        Text(group.address)
            .font(.body12Menlo)
            .foregroundColor(.turquoise600)
            .lineLimit(1)
    }
    
    var cells: some View {
        VStack(spacing: 0) {
            Separator()
            CoinCell()
        }
    }
    
    private func expandCell() {
        withAnimation {
            isExpanded.toggle()
        }
    }
    
    private func copyAddress() {
        showAlert = true
        let pasteboard = UIPasteboard.general
        pasteboard.string = group.address
    }
}

#Preview {
    ScrollView {
        ChainCell(group: GroupedChain.example)
    }
}
