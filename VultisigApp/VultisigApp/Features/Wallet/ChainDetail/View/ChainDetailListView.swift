//
//  ChainDetailListView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 22/09/2025.
//

import SwiftUI

struct ChainDetailListView: View {
    @ObservedObject var viewModel: ChainDetailViewModel
    var onPress: (Coin) -> Void
    var onManageTokens: () -> Void

    var body: some View {
        if viewModel.filteredTokens.isEmpty {
            addTokensView
        } else {
            tokensList
        }
    }

    var tokensList: some View {
        ForEach(Array(viewModel.filteredTokens.enumerated()), id: \.element.id) { index, token in
            Button {
                onPress(token)
            } label: {
                TokenCellView(coin: token)
                    .commonListItemContainer(
                        index: index,
                        itemsCount: viewModel.filteredTokens.count
                    )
            }
        }
    }

    var addTokensView: some View {
        VStack(spacing: 12) {
            Icon(named: "crypto-outline", color: Theme.colors.primaryAccent4, size: 24)
            VStack(spacing: 8) {
                Text("noTokensFound")
                    .foregroundStyle(Theme.colors.textPrimary)
                    .font(Theme.fonts.subtitle)
                Text("noTokensFoundSubtitle")
                    .foregroundStyle(Theme.colors.textTertiary)
                    .font(Theme.fonts.footnote)
            }
            .frame(maxWidth: 263)
            .multilineTextAlignment(.center)

            PrimaryButton(title: "customizeTokens", leadingIcon: "write", size: .mini, action: onManageTokens)
                .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.colors.bgSurface1))
    }
}

#Preview {
    ChainDetailListView(
        viewModel: ChainDetailViewModel(vault: .example, nativeCoin: .example),
        onPress: { _ in },
        onManageTokens: {}
    )
}
