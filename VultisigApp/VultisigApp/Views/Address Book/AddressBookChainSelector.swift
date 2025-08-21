//
//  AddressBookChainSelector.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/08/2025.
//

import SwiftUI

struct AddressBookChainSelector: View {
    @Binding var selectedChain: AddressBookChainType
    let coins: [CoinMeta]
    
    var body: some View {
        NavigationLink {
            AddressBookChainSelectionScreen(selectedChain: $selectedChain, vaultChains: coins)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text("chain".localized)
                    .foregroundColor(Theme.colors.textPrimary)
                    .font(Theme.fonts.bodySMedium)
                BoxView {
                    HStack {
                        AddressBookChainView(chain: selectedChain)
                        Spacer()
                        Icon(named: "chevron-right", color: Theme.colors.textPrimary, size: 20)
                    }
                }
            }
        }
    }
}
