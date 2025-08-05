//
//  SendCryptoTransactionHashRowView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 28/07/2025.
//


import SwiftUI

struct SendCryptoTransactionHashRowView: View {
    @Environment(\.openURL) var openURL
    
    let hash: String
    let explorerLink: String
    let showCopy: Bool
    @Binding var showAlert: Bool
    
    var body: some View {
        HStack(spacing: 32) {
            Text(NSLocalizedString("transactionHash", comment: ""))
                .foregroundColor(.extraLightGray)
                .lineLimit(1)
                .truncationMode(.tail)
            
            Spacer()
            
            HStack(spacing: 8) {
                if showCopy {
                    hashWithCopyView
                } else {
                    hashView
                }
                
                explorerLinkView
            }
        }
        .font(Theme.fonts.bodySMedium)
    }
    
    var explorerLinkView: some View {
        Button {
            if let url = URL(string: explorerLink) {
                openURL(url)
            }
        } label: {
            Image(systemName: "arrow.up.forward.app")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16)
                .foregroundColor(.neutral0)
        }
    }
    
    var hashWithCopyView: some View {
        Button {
            copyHash()
        } label: {
            HStack(spacing: 2) {
                hashView
                Image(systemName: "doc.on.clipboard")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                    .foregroundColor(.neutral0)
            }
        }
    }
    
    var hashView: some View {
        Text(hash)
            .foregroundColor(.neutral0)
            .lineLimit(1)
            .truncationMode(.middle)
    }
    
    func copyHash() {
        showAlert = true
        ClipboardManager.copyToClipboard(hash)
    }
}

#Preview {
    SendCryptoTransactionHashRowView(
        hash: "294FF0BCDDA7E79140782FB3F5F759FFEE1C11639194FF500BAB6D92012C615C",
        explorerLink: "https://thorchain.net/tx/294FF0BCDDA7E79140782FB3F5F759FFEE1C11639194FF500BAB6D92012C615C",
        showCopy: true,
        showAlert: .constant(false)
    )
}
