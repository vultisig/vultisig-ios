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
                row(for: token)
                    .commonListItemContainer(
                        index: index,
                        itemsCount: viewModel.filteredTokens.count
                    )
            }
        }
        .commonListContainer()
    }

    /// A row is either a navigation target or an activation prompt — never both.
    ///
    /// The "Activate" CTA is a `Button`, and a `Button` inside another `Button`'s
    /// label hit-tests unreliably: the CTA's tap can be taken by the row and open
    /// coin detail instead of the activation sheet. Overlaying a row-wide tap
    /// gesture on the CTA instead would only move the ambiguity into gesture
    /// arbitration. Splitting the two cases leaves them structurally unable to
    /// overlap, so neither has to win anything.
    ///
    /// A token whose trust line is missing can neither hold nor receive a balance,
    /// so coin detail has nothing to show for it — that row drops the navigation
    /// tap (and, in the cell, the chevron that advertised it) and offers only the
    /// action that applies. Every other row keeps the plain `Button` it always had,
    /// press feedback and keyboard activation included.
    @ViewBuilder
    private func row(for token: Coin) -> some View {
        if let activate = activateAction(for: token) {
            TokenCellView(coin: token, onActivate: activate)
        } else {
            Button {
                onPress(token)
            } label: {
                TokenCellView(coin: token)
            }
        }
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
        .background(Theme.radius.xl.shape.fill(Theme.colors.bgSurface1))
    }
}

#Preview {
    ChainDetailListView(
        viewModel: ChainDetailViewModel(vault: .example, nativeCoin: .example),
        onPress: { _ in },
        onManageTokens: {}
    )
}
