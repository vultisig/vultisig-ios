//
//  AddressBookCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-11.
//

import SwiftUI

struct AddressBookCell: View {
    let title: String
    let address: String
    let coin: CoinMeta
    
    @EnvironmentObject var viewModel: AddressBookViewModel
    
    var body: some View {
        HStack(spacing: 8) {
            rearrangeIcon
            content
            deleteIcon
        }
    }
    
    var content: some View {
        HStack(spacing: 12) {
            logo
            text
        }
        .padding(12)
        .background(Color.blue600)
        .cornerRadius(10)
    }
    
    var logo: some View {
        Image(coin.logo)
            .resizable()
            .frame(width: 32, height: 32)
    }
    
    var text: some View {
        VStack(alignment: .leading, spacing: 8) {
            titleContent
            addressContent
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var titleContent: some View {
        Text(title)
            .foregroundColor(.neutral0)
            .font(.body14MontserratSemiBold)
    }
    
    var addressContent: some View {
        Text(address)
            .foregroundColor(.neutral0)
            .font(.body12Menlo)
            .lineLimit(1)
            .truncationMode(.middle)
    }
    
    var rearrangeIcon: some View {
        Image(systemName: "square.grid.4x3.fill")
            .font(.body24MontserratMedium)
            .rotationEffect(.degrees(90))
            .foregroundColor(.neutral300)
            .scaleEffect(viewModel.isEditing ? 1 : 0)
            .frame(width: viewModel.isEditing ? nil : 0)
    }
    
    var deleteIcon: some View {
        Image(systemName: "trash")
            .font(.body24MontserratMedium)
            .foregroundColor(.neutral0)
            .scaleEffect(viewModel.isEditing ? 1 : 0)
            .frame(width: viewModel.isEditing ? nil : 0)
    }
}

#Preview {
    ZStack {
        Background()
        VStack {
            AddressBookCell(
                title: "Online Wallet",
                address: "0x0cb1D4a24292bB89862f599Ac5B10F42b6DE07e4",
                coin: CoinMeta.example
            )
            
            AddressBookCell(
                title: "Online Wallet",
                address: "0x0cb1D4a24292bB89862f599Ac5B10F42b6DE07e4",
                coin: CoinMeta.example
            )
        }
    }
    .environmentObject(AddressBookViewModel())
}
