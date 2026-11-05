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
        HStack(spacing: 6) {
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
            .settingsText(.bodyM)
            .foregroundStyle(Theme.colors.textPrimary)
    }
}
