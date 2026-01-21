//
//  AddressBookChainCellView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/08/2025.
//

import SwiftUI

struct AddressBookChainCellView: View {
    let chain: AddressBookChainType

    var body: some View {
        HStack {
            iconImage
            nameText
        }
    }

    var iconImage: some View {
        AsyncImageView(
            logo: chain.icon,
            size: CGSize(width: 32, height: 32),
            ticker: "",
            tokenChainLogo: nil
        )
    }

    var nameText: some View {
        Text(chain.name)
            .font(Theme.fonts.bodySMedium)
            .foregroundColor(Theme.colors.textPrimary)
    }
}
