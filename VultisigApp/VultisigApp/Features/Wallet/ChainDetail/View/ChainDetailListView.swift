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
    /// Invoked for an XRPL token with no trust line. `nil` on chains that have no
    /// activation step.
    var onActivate: ((Coin) -> Void)?

    var body: some View {
        if viewModel.filteredTokens.isEmpty {
            addTokensView
        } else {
            tokensList
        }
    }

    var tokensList: some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.filteredTokens.enumerated()), id: \.element.id) { index, token in
                // The row's tap is a gesture on the cell rather than a `Button`
                // wrapping it. A row can carry its own "Activate" `PrimaryButton`,
                // and a `Button` inside another `Button`'s label hit-tests
                // unreliably — a tap on Activate can be swallowed by the row and
                // navigate to coin detail instead of opening the activation sheet.
                // Kept as siblings, the inner button takes the tap and the rest of
                // the row still opens coin detail.
                TokenCellView(
                    coin: token,
                    onActivate: activateAction(for: token)
                )
                .contentShape(Rectangle())
                .onTapGesture { onPress(token) }
                .accessibilityAddTraits(.isButton)
                .commonListItemContainer(
                    index: index,
                    itemsCount: viewModel.filteredTokens.count
                )
            }
        }
        .commonListContainer()
    }

    /// The activation closure for a row, or `nil` when the row should render a
    /// balance as usual. Resolved here so the cell stays a dumb renderer.
    private func activateAction(for token: Coin) -> (() -> Void)? {
        guard let onActivate, viewModel.needsTrustLine(token) else { return nil }
        return { onActivate(token) }
    }

    var addTokensView: some View {
        VStack(spacing: 12) {
            Icon(.circleDashed, color: Theme.colors.primaryAccent4, size: 24)
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

            PrimaryButton(title: "customizeTokens", leadingIcon: .compose2, size: .mini, action: onManageTokens)
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
