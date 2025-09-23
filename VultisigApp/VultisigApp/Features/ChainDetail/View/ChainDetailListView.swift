//
//  ChainDetailListView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 22/09/2025.
//

import SwiftUI

struct ChainDetailListView: View {
    @ObservedObject var viewModel: ChainDetailViewModel
    var onPress: () -> Void
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
            let isFirst = index == 0
            let isLast = index == viewModel.filteredTokens.count - 1
            
            VStack(spacing: 0) {
                GradientListSeparator()
                    .showIf(isFirst)
                TokenCellView(coin: token)
                Separator(color: Theme.colors.borderLight, opacity: 1)
                    .showIf(!isLast)
            }
            .clipShape(
                .rect(
                    topLeadingRadius: isFirst ? 12 : 0,
                    bottomLeadingRadius: isLast ? 12 : 0,
                    bottomTrailingRadius: isLast ? 12 : 0,
                    topTrailingRadius: isFirst ? 12 : 0
                )
            )
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
                    .foregroundStyle(Theme.colors.textExtraLight)
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
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.colors.bgSecondary))
    }
}

#Preview {
    ChainDetailListView(
        viewModel: ChainDetailViewModel(vault: .example, group: .example),
        onPress: {},
        onManageTokens: {}
    )
}
