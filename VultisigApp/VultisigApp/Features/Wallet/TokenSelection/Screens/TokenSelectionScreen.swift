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
        // Local-first: held, then curated presets, then verified provider breadth.
        // Browse hides `.unverified` — typing a query is what reveals the badged
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
        .onReceive(tokenViewModel.$searchText) { _ in
            tokenViewModel.updateSearchedTokens()
        }
        .alert(
            "addUnverifiedTokenTitle".localized,
            isPresented: $showUnverifiedAddConfirm
        ) {
            Button("cancel".localized, role: .cancel) {}
            Button("continueAnyway".localized, role: .destructive) {
                persistSelection()
            }
        } message: {
            Text(unverifiedAddConfirmMessage)
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

    /// The confirm copy plus each unverified token's ticker and full contract
    /// address, so the user can actually perform the "make sure the contract is
    /// correct" check the message asks for (a bare ticker is exactly what an
    /// impersonator clones).
    private var unverifiedAddConfirmMessage: String {
        let base = "addUnverifiedTokenMessage".localized
        let details = unverifiedAdditions
            .map { coin in
                let contract = coin.contractAddress.isEmpty ? coin.ticker : coin.contractAddress
                return "\(coin.ticker)\n\(contract)"
            }
            .joined(separator: "\n\n")
        return details.isEmpty ? base : base + "\n\n" + details
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
