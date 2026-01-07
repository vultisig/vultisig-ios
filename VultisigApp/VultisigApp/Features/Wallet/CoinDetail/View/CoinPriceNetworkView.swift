//
//  CoinPriceNetworkView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 29/09/2025.
//

import SwiftUI

struct CoinPriceNetworkView: View {
    let chainName: String
    let price: String
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                rowView(title: "price".localized, description: price)
                Separator().padding(.horizontal, 2)
                rowView(title: "network".localized, description: chainName)
            }
            GradientListSeparator()
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.colors.bgPrimary))
        .clipShape(
            .rect(
                topLeadingRadius: 12,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 12
            )
        )
    }
    
    func rowView(title: String, description: String) -> some View {
        HStack {
            Text(title)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)
            Spacer()
            Text(description)
                .font(Theme.fonts.priceFootnote)
                .foregroundStyle(Theme.colors.textSecondary)
                .padding(.vertical, 3)
                .padding(.horizontal, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.colors.bgSurface2))
        }
        .padding(16)
    }
}

#Preview {
    CoinPriceNetworkView(chainName: "TRON", price: "$214")
}
