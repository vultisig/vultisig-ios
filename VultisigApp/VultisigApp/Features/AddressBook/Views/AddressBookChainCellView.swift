//
//  AddressBookChainCellView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/08/2025.
//

import SwiftUI

struct AddressBookChainCellView: View {
    /// `.field` is the value inside the chain selector field.
    enum Style {
        case row, field
    }

    let chain: AddressBookChainType
    var style: Style = .row

    var body: some View {
        HStack(spacing: style == .field ? 6 : nil) {
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
        Group {
            switch style {
            case .row: Text(chain.name).font(Theme.fonts.bodySMedium)
            case .field: Text(chain.name).settingsText(.bodyM)
            }
        }
        .foregroundStyle(Theme.colors.textPrimary)
    }
}
