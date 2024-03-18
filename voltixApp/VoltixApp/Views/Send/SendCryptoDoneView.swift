//
//  SendCryptoDoneView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-17.
//

import SwiftUI

struct SendCryptoDoneView: View {
    var body: some View {
        VStack {
            view
            button
        }
    }
    
    var view: some View {
        ScrollView {
            card
        }
    }
    
    var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("transaction", comment: "Transaction"))
                .font(.body20MontserratSemiBold)
                .foregroundColor(.neutral0)
            
            Text("bc1psrjtwm7682v6nhx2uwfgcfelrennd7pcvqq7v6w")
                .font(.body13Menlo)
                .foregroundColor(.turquoise600)
        }
        .padding(16)
        .background(Color.blue600)
        .cornerRadius(10)
        .padding(.horizontal, 16)
    }
    
    var button: some View {
        FilledButton(title: "complete")
            .padding(40)
    }
}

#Preview {
    SendCryptoDoneView()
}
