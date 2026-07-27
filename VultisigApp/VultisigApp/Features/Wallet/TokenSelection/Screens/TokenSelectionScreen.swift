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
        let assets = tokenViewModel.searchText.isEmpty ?
            tokenViewModel.selectedTokens + tokenViewModel.preExistTokens :
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
            emptyStateBuilder: { EmptyView() },
            headerAccessory: { unverifiedToggle }
        )
        .onAppear {
            tokenViewModel.loadData(chain: chain, vault: vault)
        }
        .onDisappear {
            tokenViewModel.cancelLoading()
        }
        .onReceive(tokenViewModel.$searchText) { _ in
            tokenViewModel.updateSearchedTokens(chain: chain, vault: vault)
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
            Text("addUnverifiedTokenMessage".localized)
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

    /// Opt-in reveal of the withheld unverified search results. Shown only when
    /// there are unverified candidates to reveal (otherwise it's noise). Routes
    /// through `setShowUnverified` so the visible lists re-derive immediately.
    @ViewBuilder
    private var unverifiedToggle: some View {
        if tokenViewModel.hasUnverifiedResults {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("showUnverifiedTokensTitle".localized)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textPrimary)
                    Text("showUnverifiedTokensSubtitle".localized)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                VultiToggle(isOn: Binding(
                    get: { tokenViewModel.showUnverified },
                    set: { tokenViewModel.setShowUnverified($0, chain: chain, vault: vault) }
                ))
            }
            .padding(.trailing, 16)
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
