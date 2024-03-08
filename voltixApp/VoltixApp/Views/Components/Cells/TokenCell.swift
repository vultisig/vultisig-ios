//
//  TokenCard.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-08.
//

import SwiftUI

struct TokenCell: View {
    @State var isExpanded = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            main
            cells
        }
        .padding(.vertical, 4)
        .background(Color.blue600)
        .cornerRadius(10)
        .padding(16)
    }
    
    var main: some View {
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
        Text("BTC")
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
        Image(systemName: "qrcode")
            .foregroundColor(.neutral0)
            .font(.body18MenloMedium)
    }
    
    var amount: some View {
        Text("$0.0")
            .font(.body20MontserratSemiBold)
            .foregroundColor(.neutral0)
    }
    
    var address: some View {
        Text("tx.fromAddress")
            .font(.body12Menlo)
            .foregroundColor(.turquoise600)
            .lineLimit(1)
    }
    
    var cells: some View {
        VStack(spacing: 0) {
            Separator()
            TokenAssetCell()
            Separator()
            TokenAssetCell()
        }
    }
}

#Preview {
    TokenCell()
}
