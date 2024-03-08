//
//  TokenAssetCell.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-08.
//

import SwiftUI

struct TokenAssetCell: View {
    var body: some View {
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
        Text("ETH")
            .font(.body20Menlo)
            .foregroundColor(.neutral0)
    }
    
    var quantity: some View {
        Text("1.1")
            .font(.body16Menlo)
            .foregroundColor(.neutral0)
    }
    
    var amount: some View {
        Text("$60,899")
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
        Text(NSLocalizedString("swap", comment: "Swap button text").uppercased())
            .font(.body16MenloBold)
            .foregroundColor(.blue200)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(Color.blue800)
            .cornerRadius(50)
    }
    
    var sendButton: some View {
        Text(NSLocalizedString("send", comment: "Send button text").uppercased())
            .font(.body16MenloBold)
            .foregroundColor(.turquoise600)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(Color.blue800)
            .cornerRadius(50)
    }
}

#Preview {
    TokenAssetCell()
}
