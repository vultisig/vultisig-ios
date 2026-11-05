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

    private static let fieldHeight: CGFloat = 56

    var body: some View {
        Button {
            presentSelector = true
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text("chain".localized)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .settingsText(.bodyS)
                HStack {
                    AddressBookChainCellView(chain: selectedChain)
                    Spacer()
                    Icon(.chevronRightSmall, color: Theme.colors.textPrimary, size: 20)
                }
                .padding(.horizontal, 16)
                .frame(height: Self.fieldHeight)
                .background(
                    Theme.radius.lg.shape
                        .fill(Theme.colors.bgSurface1)
                        .strokeBorder(Theme.colors.borderLight, lineWidth: 1)
                )
            }
        }

    }
}
