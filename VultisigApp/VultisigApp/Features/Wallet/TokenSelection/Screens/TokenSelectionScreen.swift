//
//  TokenSelectionScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 26/09/2025.
//

import SwiftUI

enum TokenSelectionAsset: Hashable {
    case custom
    case token(CoinMeta)
}

struct TokenSelectionScreen: View {
    let vault: Vault
    let chain: Chain
    @Binding var isPresented: Bool
    var onCustomToken: () -> Void

    @StateObject var tokenViewModel = TokenSelectionViewModel()
    @EnvironmentObject var coinViewModel: CoinSelectionViewModel

    @State private var showUnverifiedAddConfirm = false

    var elements: [TokenSelectionAsset] {
        // Local-first: held, then curated presets, then the best N of each
        // provider's verified breadth. Browse is a shortlist, not the catalog —
        // typing a query searches the whole of it, including the badged
        // unverified long-tail (`searchedTokens`).
        let assets = tokenViewModel.searchText.isEmpty ?
            tokenViewModel.selectedTokens + tokenViewModel.preExistTokens + tokenViewModel.browseProviderTokens :
            tokenViewModel.searchedTokens
        return [.custom] + assets.map { .token($0) }
    }

    var sections: [AssetSection<Int, TokenSelectionAsset>] {
        !elements.isEmpty ? [AssetSection(assets: elements)] : []
    }

    var body: some View {
        AssetSelectionContainerSheet(
            title: "selectTokensTitle".localized,
            subtitle: "selectTokensSubtitle".localized,
            isPresented: $isPresented,
            searchText: $tokenViewModel.searchText,
            elements: sections,
            onSave: onSave,
            cellBuilder: cellBuilder,
            emptyStateBuilder: { EmptyView() }
        )
        .onAppear {
            tokenViewModel.loadData(chain: chain, vault: vault)
        }
        .onDisappear {
            tokenViewModel.cancelLoading()
        }
        .bottomSheet(isPresented: $showUnverifiedAddConfirm) {
            UnverifiedTokenBottomSheet {
                showUnverifiedAddConfirm = false
            } onContinue: {
                showUnverifiedAddConfirm = false
                persistSelection()
            }
        }
    }

    /// Newly-added tokens in the pending selection that the catalog flagged
    /// `.unverified` — drives the add-confirm. Tokens already held by the vault
    /// aren't re-confirmed (this only guards *adding* an unverified token).
    private var unverifiedAdditions: [CoinMeta] {
        coinViewModel.selection.filter { coin in
            tokenViewModel.verification(for: coin) == .unverified && vault.coin(for: coin) == nil
        }
    }

    @ViewBuilder
    func cellBuilder(_ asset: TokenSelectionAsset, _: Int) -> some View {
        switch asset {
        case .custom:
            CustomTokenGridCell(action: onCustomToken)
        case .token(let coin):
            TokenSelectionGridCell(
                coin: coin,
                verification: tokenViewModel.verification(for: coin),
                isSelected: coinViewModel.isSelected(asset: coin)
            ) {
                coinViewModel.handleSelection(isSelected: $0, asset: coin)
            }
        }
    }

    func onSave() {
        // Confirm before persisting when the selection adds any unverified token
        // (reuses the app's "continue anyway" risk-confirm pattern). Verified /
        // curated additions save straight through.
        if unverifiedAdditions.isEmpty {
            persistSelection()
        } else {
            showUnverifiedAddConfirm = true
        }
    }

    private func persistSelection() {
        Task {
            await CoinService.saveAssets(for: vault, selection: coinViewModel.selection)
            await MainActor.run { isPresented = false }
        }
    }
}

#Preview {
    TokenSelectionScreen(
        vault: .example,
        chain: .bitcoin,
        isPresented: .constant(true),
        onCustomToken: {}
    )
}
