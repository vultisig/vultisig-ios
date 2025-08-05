//
//  TransactionCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-04-03.
//

import SwiftUI

struct TransactionCell: View {
    let title: String
    let id: String
    let url: String
    var image: String? = nil
    
    var body: some View {
        Link(destination: URL(string: url)!) {
            cell
        }
    }
    
    var cell: some View {
        HStack(spacing: 24) {
            field
            Spacer()
            chevron
        }
    }
    
    var field: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            content
        }
    }
    
    var header: some View {
        HStack(spacing: 12) {
            if let image {
                Image(systemName: image)
            }
            
            Text(NSLocalizedString(title, comment: "Transaction ID"))
        }
        .font(Theme.fonts.bodyLMedium)
        .foregroundColor(.neutral0)
    }
    
    var content: some View {
        Text(id)
            .font(Theme.fonts.footnote)
            .foregroundColor(.turquoise600)
            .multilineTextAlignment(.leading)
    }
    
    var chevron: some View {
        Image(systemName: "chevron.forward")
            .foregroundColor(.neutral0)
            .font(Theme.fonts.bodyLMedium)
    }
}

#Preview {
    TransactionCell(
        title: "transactionID",
        id: "123456",
        url: Endpoint.bitcoinLabelTxHash("")
    )
    .background(Color.blue600)
}
