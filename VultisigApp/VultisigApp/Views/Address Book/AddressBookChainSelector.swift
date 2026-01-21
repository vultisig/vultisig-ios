//
//  AddressBookChainSelector.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/08/2025.
//

import SwiftUI

struct AddressBookChainSelector: View {
    @Binding var selectedChain: AddressBookChainType
    @Binding var presentSelector: Bool

    var body: some View {
        Button {
            presentSelector = true
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text("chain".localized)
                    .foregroundColor(Theme.colors.textPrimary)
                    .font(Theme.fonts.bodySMedium)
                ContainerView {
                    HStack {
                        AddressBookChainCellView(chain: selectedChain)
                        Spacer()
                        Icon(named: "chevron-right", color: Theme.colors.textPrimary, size: 20)
                    }
                }
            }
        }

    }
}
