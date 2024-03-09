//
//  VaultCell.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-08.
//

import SwiftUI

struct VaultCell: View {
    let vault: Vault
    
    var body: some View {
        NavigationLink {
            VaultDetailView(vault: vault)
        } label: {
            cell
        }
    }
    
    var cell: some View {
        HStack(spacing: 12) {
            logo
            text
        }
        .padding(12)
        .background(Color.blue600)
        .cornerRadius(10)
        .padding(.horizontal, 16)
    }
    
    var logo: some View {
        Image("BitcoinLogo")
            .resizable()
            .frame(width: 32, height: 32)
    }
    
    var text: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            address
        }
    }
    
    var header: some View {
        HStack(spacing: 12) {
            title
            Spacer()
            quantity
            amount
        }
    }
    
    var title: some View {
        Text(vault.name.capitalized)
            .font(.body16MontserratBold)
            .foregroundColor(.neutral100)
    }
    
    var quantity: some View {
        Text("\(vault.coins.count) assets")
            .font(.body12Menlo)
            .foregroundColor(.neutral100)
            .padding(.vertical, 2)
            .padding(.horizontal, 12)
            .background(Color.blue400)
            .cornerRadius(50)
    }
    
    var amount: some View {
        Text("$65,899")
            .font(.body16MenloBold)
            .foregroundColor(.neutral100)
    }
    
    var address: some View {
        Text("tx.fromAddress")
            .font(.body12Menlo)
            .foregroundColor(.turquoise600)
            .lineLimit(1)
    }
}

#Preview {
    VaultCell(vault: Vault.example)
}
