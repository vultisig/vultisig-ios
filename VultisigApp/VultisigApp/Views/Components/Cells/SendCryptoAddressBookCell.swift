//
//  SendCryptoAddressBookCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-07-04.
//

import SwiftUI

struct SendCryptoAddressBookCell: View {
    let title: String
    let description: String
    let icon: String?
    @ObservedObject var tx: SendTransaction
    @Binding var showSheet: Bool
    
    var body: some View {
        Button {
            handleButtonTap()
        } label: {
            label
        }
        .buttonStyle(BorderlessButtonStyle())
    }
    
    var label: some View {
        HStack {
            image
            content
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 22)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.borderBlue, lineWidth: 1)
        )
    }
    
    var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.body14BrockmannMedium)
                .foregroundColor(.neutral0)
                .lineLimit(1)
            
            Text(description)
                .font(.body12BrockmannMedium)
                .foregroundColor(.lightText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var image: some View {
        ZStack {
            if let icon {
                Image(icon)
                    .resizable()
            } else {
                placeholderImage
            }
        }
        .frame(width: 32, height: 32)
        .cornerRadius(30)
    }
    
    var placeholderImage: some View {
        let color = Color.random()
        
        return ZStack {
            color
                .opacity(0.1)
            
            Text(title.prefix(1).uppercased())
                .font(.body16BrockmannMedium)
                .foregroundColor(color)
        }
    }
    
    private func handleButtonTap() {
        tx.toAddress = description
        showSheet = false
    }
}
