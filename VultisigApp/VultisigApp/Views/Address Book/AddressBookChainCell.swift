//
//  AddressBookChainCell.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/08/2025.
//

import SwiftUI

struct AddressBookChainCell: View {
    let chain: AddressBookChainType
    let isSelected: Bool
    var onSelect: () -> Void
    
    init(chain: AddressBookChainType, isSelected: Bool = false, onSelect: @escaping () -> Void = {}) {
        self.chain = chain
        self.isSelected = isSelected
        self.onSelect = onSelect
    }
    
    var body: some View {
        Button {
            onSelect()
        } label: {
            HStack {
                AddressBookChainCellView(chain: chain)
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(isSelected ? Theme.colors.bgSurface2 : Theme.colors.bgSurface1)
        }
        .buttonStyle(.plain)
    }
}
