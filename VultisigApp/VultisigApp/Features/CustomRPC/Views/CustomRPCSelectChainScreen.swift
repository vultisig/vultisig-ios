//
//  CustomRPCSelectChainScreen.swift
//  VultisigApp
//

import SwiftUI

/// Grid of chains the user can configure a custom RPC for. Replaces the former
/// vertical list. Chains that already carry an override are marked with a
/// pencil badge; a single tap opens the per-chain editor.
struct CustomRPCSelectChainScreen: View {
    @Environment(\.router) var router
    @StateObject private var viewModel = CustomRPCSelectChainViewModel()
    @State private var searchFocused = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 4)

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 24) {
                header
                if viewModel.filteredChains.isEmpty {
                    emptyState
                } else {
                    grid
                }
            }
        }
        .screenTitle("settingsAdvancedCustomRPC".localized)
        .onAppear {
            viewModel.refresh()
        }
        .onDisappear {
            viewModel.searchText = ""
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("customRPCSelectChain".localized)
                .font(Theme.fonts.title2)
                .foregroundStyle(Theme.colors.textPrimary)
            SearchTextField(value: $viewModel.searchText, isFocused: $searchFocused)
        }
    }

    private var grid: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(viewModel.filteredChains, id: \.self) { chain in
                    CustomRPCChainGridCell(
                        chain: chain,
                        hasOverride: viewModel.hasOverride(chain)
                    ) {
                        router.navigate(to: VaultRoute.customRPCDetail(chain: chain))
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            ErrorMessage(text: "noResultFound")
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

/// A single 4-col grid tile rendering a chain logo, name, and — when an
/// override exists — a pencil badge in the bottom-trailing corner.
private struct CustomRPCChainGridCell: View {
    let chain: Chain
    let hasOverride: Bool
    var onSelection: () -> Void

    var body: some View {
        Button(action: onSelection) {
            VStack(spacing: 11) {
                tile
                Text(chain.name)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(width: 74)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var tile: some View {
        AsyncImageView(
            logo: chain.logo,
            size: CGSize(width: 40, height: 40),
            ticker: chain.ticker,
            tokenChainLogo: chain.logo
        )
        .frame(width: 74, height: 74)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Theme.colors.bgSurface1)
        )
        .overlay(hasOverride ? editedOverlay : nil)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    /// Matches `AssetSelectionGridCell`'s selected treatment: the corner badge is
    /// drawn first and the inset border on top, so the border stays continuous
    /// around the badge instead of being broken by it.
    private var editedOverlay: some View {
        ZStack(alignment: .bottomTrailing) {
            Icon(named: "pencil", color: Theme.colors.textPrimary, size: 8)
                .padding(8)
                .background(
                    UnevenRoundedRectangle(
                        cornerRadii: .init(
                            topLeading: 24,
                            bottomLeading: 0,
                            bottomTrailing: 24,
                            topTrailing: 0
                        )
                    )
                    .fill(Theme.colors.border)
                )
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(Theme.colors.border, lineWidth: 1.5)
        }
    }
}
