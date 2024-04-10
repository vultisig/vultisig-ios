//
//  ChainCell.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-08.
//

import SwiftUI

struct ChainCell: View {
    let group: GroupedChain
    
    @State var showAlert = false
    @State var showQRcode = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            logo
            content
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 24)
        .background(Color.blue600)
        .cornerRadius(10)
        .padding(.horizontal, 16)
    }
    
    var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            address
        }
    }
    
    var header: some View {
        HStack(spacing: 8) {
            title
            Spacer()
            quantity
            balance
        }
        .lineLimit(1)
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
    
    var address: some View {
        Text(group.address)
            .font(.body12Menlo)
            .foregroundColor(.turquoise600)
            .lineLimit(1)
    }
    
    var quantity: some View {
        Text(getQuantity())
            .font(.body12Menlo)
            .foregroundColor(.neutral100)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.blue400)
            .cornerRadius(50)
    }
    
    var balance: some View {
        Text("$12345")
            .font(.body16MenloBold)
            .foregroundColor(.neutral100)
    }
    
    private func getQuantity() -> String {
        guard group.coins.count>1 else {
            return "1 " + NSLocalizedString("asset", comment: "")
        }
        
        return "\(group.coins.count) \(NSLocalizedString("assets", comment: ""))"
    }
}

#Preview {
    ScrollView {
        ChainCell(group: GroupedChain.example)
    }
}
