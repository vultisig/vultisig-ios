//
//  AddressQRCodeHeader.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-08-09.
//

import SwiftUI

struct AddressQRCodeHeader: View {
    let vault: Vault
    let chain: Chain
    @ObservedObject var shareSheetViewModel: ShareSheetViewModel

    var body: some View {
        HStack {
            leadingAction
            Spacer()
            text
            Spacer()
            trailingAction
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 40)
        .padding(.top, 8)
    }

    var leadingAction: some View {
        NavigationBackButton()
    }

    var text: some View {
        Text(NSLocalizedString("address", comment: "AddressQRCodeView title"))
            .foregroundStyle(Theme.colors.textPrimary)
            .font(.title3)
    }

    var trailingAction: some View {
        NavigationQRShareButton(
            vault: vault,
            type: .Address,
            viewModel: shareSheetViewModel,
            title: chain.name
        )
    }
}

#Preview {
    AddressQRCodeHeader(
        vault: Vault.example,
        chain: .bitcoin,
        shareSheetViewModel: ShareSheetViewModel()
    )
}
